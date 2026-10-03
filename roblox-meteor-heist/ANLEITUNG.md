# ☄️ METEOR HEIST – Schritt-für-Schritt-Anleitung

Dein eigenes Roblox-Spiel mit der Grundbasis von „Steal an Egg“, aber eigenem Thema:

> **Meteore fahren auf dem Laufband vorbei → du kaufst sie (E) → sie fliegen von allein in deine Base →
> ein Alien schlüpft → es bringt Geld → du klaust bei anderen → die anderen bonken dich → Rebirth →
> immer bessere Meteore und Aliens.**

---

## 📦 Was alles drin ist

| Bereich | Inhalt |
|---|---|
| **Kern-Loop** | In der Map-Mitte fährt ein langes **Laufband** mit Meteoren (ca. 1 pro Sekunde). **E** drücken = kaufen → der Meteor fliegt **automatisch** in einen freien Platz deiner Base |
| **Schlüpfen** | Im Platz zählt der Meteor herunter (🐣 8 s bei Common bis 6 min bei Secret). Dann schlüpft ein **Alien**: Normal (75 %), Selten (22 %, x2,5 Geld) oder Ultra (3 %, x6 Geld). **Erst das Alien verdient Geld** |
| **Einsammeln** | Geld sammelt sich an. Lauf über das **grüne Pad** oder einen **deiner Plätze**, um es einzusammeln |
| **Klauen** | Bei fremden Basen **E** halten → Meteor oder Alien tragen → in deine Base rennen |
| **Verteidigen** | **Bonk-Schläger** (Klick): getroffene Diebe verlieren die Beute (sie fliegt zurück). Rotes **Lock-Pad** sperrt deine Base für 60 s |
| **Aufladen** | Aliens in deiner Base leveln auf (Lv 1 → 20, ca. 3 h, +10 % Geld pro Level). Große Aliens sind Gold wert, auch zum Klauen |
| **Meteoritenschauer** | Alle 8 Minuten: 60 s lang **keine Locks**, 3x Glück, viel mehr Meteore auf dem Band → Chaos |
| **Speed Farm** | Auf dem Spawn-Platz stehen **7 Laufbänder** (Holz → Regenbogen). Drauf laufen = **Schritte 👟** sammeln (fliegende „+X 👟“-Zahlen). Mehr Schritte = schneller (16 bis 80). Bessere Laufbänder werden mit genug Schritten freigeschaltet |
| **Lange Progression** | 28 Meteore in 9 Seltenheiten (Common → Secret), 96 Aliens, Preise bis in die Billionen, Celestial/Divine/Secret erst nach Rebirth kaufbar (klauen geht immer) |
| **👑 Admin-Meteore** | 4 krasse Meteore (Rainbow Overlord, Godly Sun, Void Emperor, Chaos Core), die **nie von selbst** kommen. Nur du spawnst sie im Admin-Panel |
| **Index** | Alle Aliens sammeln, jedes neue Alien gibt dauerhaft **+1 % Einkommen** |
| **Rebirth** | +50 % Einkommen und +25 % Schritte für immer, schaltet neue Seltenheiten frei (Schritte + Index bleiben) |
| **Tagesbonus** | Mit Streak bis Tag 7 |
| **Offline** | 25 % Einkommen für bis zu 3 h, und Meteore schlüpfen auch, während du weg bist |
| **Geld-Einnahmen** | 6 Gamepasses + 8 Developer Products + Premium-Bonus |
| **Admin-Panel** | Nur für dich (automatisch, weil dir das Spiel gehört): Meteore und Admin-Meteore spawnen, Meteorregen, Geld/Rebirths/Schritte setzen, Pässe schenken, Glück-Events und Schauer (auch auf ALLEN Servern), Nachrichten, Kick/Bann/Entbannen, Reset, Teleport, Admin Abuse, Foto-Modus |
| **Grafik** | Helles Sonnenlicht mit „Future“-Beleuchtung, Atmosphäre, Wolken, leichtes Leuchten. Knallgrüner Roblox-Rasterboden wie in Simulator-Spielen |
| **Flüssig** | Die Meteore auf dem Laufband bewegt jeder Spieler selbst auf seinem Gerät (kein Server-Ruckeln). Fenster, Knöpfe und Zahlen sind animiert |
| **Technik** | Sicheres Speichern mit Session-Lock (keine Duplikate, kein Datenverlust), Käufe doppelt abgesichert, alles serverseitig geprüft (Exploiter können nichts schummeln), globale Top-10-Bestenliste |

Die **komplette Map baut sich automatisch** per Code. Du musst in Studio nichts zusammenbauen.

---

## 🚀 SCHRITT 1 – Spiel in Roblox Studio öffnen

1. Installiere **Roblox Studio**: https://create.roblox.com → „Start Creating“.
2. Lade die Datei **`MeteorHeist.rbxlx`** aus diesem Ordner herunter
   (auf GitHub: Datei anklicken → Download-Button „Download raw file“).
3. Öffne Roblox Studio → **File → Open from File…** → `MeteorHeist.rbxlx` wählen.

## 👑 SCHRITT 2 – Admin-Panel (passiert automatisch!)

Du musst **nichts** eintragen. **Nur du** bist Admin, weil das Spiel deinem Account gehört.
Niemand sonst ist Admin, und Admin kann man **nicht kaufen**. Der Server prüft das bei jeder
Aktion, auch Hacker kommen nicht an das Panel. (Beim Testen in Studio bist du sowieso Admin.)

## ▶️ SCHRITT 3 – Testen

1. Oben auf **Play** (F5) klicken.
2. Du spawnst in deiner Base. Lauf zum **Laufband** in der Mitte und drück **E** an einem Meteor.
   Er fliegt von allein in deine Base. Nach ein paar Sekunden schlüpft ein **Alien**.
3. Lauf über das **grüne Pad** (oder einen deiner Plätze), um Geld einzusammeln. Das **rote Pad** sperrt deine Base.
4. Rechts auf **🏃 Laufbänder** → **Zu den Laufbändern!** → auf dem Holz-Laufband laufen = Schritte sammeln.
5. Admin-Panel: Taste **P** oder Button **🛠️ Admin** rechts.
6. Mehrere Spieler testen: **Test → Clients and Servers → 2 Players → Start**, dann kannst du dich selbst beklauen.

**Tasten:** **E** = kaufen / klauen, **F** = verkaufen (in deiner Base), **P** = Admin-Panel,
**G** = Fliegen (nur Admin), **H** = Foto-Modus (nur Admin).

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
| ☄️ +6 Plätze | 199 R$ | | 🏦 Cash XL | 399 R$ |
| 🤖 Auto Collect | 149 R$ | | 🍀 2x Server-Glück | 79 R$ |
| ⚡ 2x Schlüpfen & Wachsen | 299 R$ | | 🌠 Meteoritenschauer | 49 R$ |
| 👟 2x Schritte | 99 R$ | | 👟 Schritte-Paket | 39 R$ |
| | | | 🌟 Legendary Meteor | 149 R$ |
| | | | 🔮 Mythic Meteor | 449 R$ |

**Warum das zieht:** Server-Glück und Meteoritenschauer werden **allen im Server angekündigt**
(„Max hat 2x Glück für ALLE gekauft!“). Das macht andere neugierig und sie kaufen auch.
Cash-Pakete und das Schritte-Paket skalieren mit dem Fortschritt, bleiben also auch für Profis interessant.
Der Angebots-Knopf **„👟 2x Schritte – NUR … R$“** links im Spiel erscheint, sobald die Pass-ID eingetragen ist.

**Premium Payouts:** Roblox zahlt dir automatisch Robux, wenn Premium-Mitglieder dein Spiel spielen.
Premium-Spieler bekommen im Spiel +10 % (Anreiz, länger zu bleiben).

**Auszahlung in echtes Geld (DevEx):** ab 13 Jahren, verifizierte E-Mail + ID, Mindestbetrag laut
Roblox (aktuell 30.000 verdiente Robux). Infos: https://create.roblox.com/dashboard/devex

## 📈 SCHRITT 6 – Spieler bekommen

Die Technik ist für sehr viele Spieler gebaut (siehe unten), aber **ob 100.000 Leute kommen, hängt am
Marketing und am Roblox-Algorithmus**. Das kann niemand garantieren. Was am meisten hilft:

1. **Icon + Thumbnails**: knallig, ein riesiger glühender Meteor, ein Alien, ein Spieler der flüchtet. Titel mit Emoji: `☄️ Meteor Heist`.
2. **Erste 5 Minuten** entscheiden. Das Spiel gibt sofort Geld, der erste Meteor schlüpft nach 8 Sekunden, perfekt dafür.
3. **Updates jede Woche** (neue Meteore/Aliens/Events) → „UPDATE 🔥“ im Titel. Schreib mir einfach, was rein soll.
4. **TikTok/YouTube Shorts**: „Ich habe ein ULTRA-Alien geklaut 😱“ Clips.
5. **Roblox-Werbung** (Ads Manager): mit kleinem Budget testen, sobald die Spielzeit pro Spieler gut ist.
6. **Codes & Events** am Wochenende (Admin-Panel → Glück auf ALLEN Servern).

## 🛠️ Admin-Panel – was kann es?

| Bereich | Funktion |
|---|---|
| 🎯 Ziel | `me`, `all`, `others`, (Teil vom) Spielernamen oder UserId. „Spieler laden“ zeigt alle im Server. Über deinem Kopf steht im echten Spiel 🛠️ ADMIN |
| 👑 Admin-Meteore | Je Admin-Meteor: **Gratis in die Mitte** (landet mit großem Knall in der Gratis-Zone am Spawn-Platz, Ansage an alle, wer zuerst da ist, bekommt ihn) oder **In meine Base** (schlüpft nach 5 s). Dazu **Admin-Meteor-Regen** (1-8 zufällige Admin-Meteore gratis) |
| ☄️ Spawnen | Jeden Meteor + Mutation wählen → **Aufs Laufband**, **Vor mir**, **Gratis vor mir**, **Gratis-Zone**, **In Ziel-Base** (inkl. Level) |
| 🌧️ Meteorregen | 10-40 Meteore einer Seltenheit kommen nacheinander aufs Laufband |
| 💰 Werte | Cash geben/setzen, Rebirths setzen, **Schritte setzen**, Gamepässe schenken (bis Server-Wechsel) |
| 🎉 Events | X-fach Glück für Y Minuten, Meteoritenschauer, Nachricht an alle. Mit 🌍 **auf ALLEN Servern gleichzeitig** |
| 🛡️ Moderation | Kick, Bann (Tage oder für immer, gilt fürs ganze Spiel), Entbannen per UserId, Base leeren, Spielstand zurücksetzen, Teleport zu/holen, Laufband + Gratis-Zone leeren. Bann/Reset brauchen einen zweiten Klick |
| 😈 Admin Abuse | **Fliegen/Schweben** (Taste **G**: WASD + Leertaste hoch, Shift runter), **ADMIN-ABUSE-EVENT** (10x Glück, Schauer, Geld für alle, Gratis-Secrets und ein Admin-Meteor in der Gratis-Zone, Mond-Schwerkraft, auch auf allen Servern), Mond-Schwerkraft an/aus, Spieler einfrieren/auftauen, riesig/mini/normal, unsichtbar |
| 📸 Foto-Modus | Für schöne Thumbnails: **UI aus/an** (Taste **H**: alle Knöpfe, Roblox-Leisten und E-Hinweise weg, nochmal **H** = zurück), **Showcase-Reihe** (je ein Meteor jeder Seltenheit vor dir, bleibt 5 Min), **Foto-Base** (leere Plätze deiner Base mit Deko-Aliens füllen, nur zum Anschauen, wird nicht gespeichert), **Foto aufräumen** (Deko weg, Laufband + Gratis-Zone leer) |

## ⚙️ Balancing – alles in `Config`

Alles steht kommentiert in `ReplicatedStorage → Shared → Config`:
- **Neuen Meteor** hinzufügen: eine Zeile in `Config.Meteors` kopieren, neue `Id` vergeben.
  Danach in `Shared → Aliens` die **3 Aliens** für diesen Meteor eintragen (eine Zeile pro Alien).
- Spawnchancen und **Schlüpfzeit**: `Config.Rarities` (Weight, HatchTime). Preise/Einkommen pro Meteor.
- **Laufbänder**: `Config.Treadmills` (Name, ab wie vielen Schritten, Schritte pro Tick, Farbe).
- **Laufband in der Mitte**: `Config.BeltSpawnInterval` (wie oft ein Meteor kommt), `Config.BeltSpeed` (Tempo).
- Schauer-Takt, Lock-Dauer, Rebirth-Kosten, Aufladezeit …
- ⚠️ **`DataStoreName` nie ändern**, sonst sind alle Spielstände weg.
- ⚠️ **Ids** von Meteoren und Aliens nie umbenennen (sie stehen in den Spielständen).

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
| Admin-Panel fehlt im echten Spiel | Das Spiel muss unter **deinem** Account veröffentlicht sein (bei „Owner“ dein Name, keine Gruppe) |
| Shop zeigt „Bald verfügbar“ | Die ID in `Config` ist noch `0` |
| „Server voll – keine Base frei“ | Max Players auf 8 stellen (Schritt 4.3) |
| Rote Fehler im **Output**-Fenster | Text kopieren und mir hier schicken, ich fixe es |
| Kauf kam nicht an | Roblox wiederholt den Kauf automatisch, bis er verbucht ist. Nichts geht verloren |
| „Zu weit weg“ beim Kaufen | Näher ans Geländer vom Laufband gehen. Der Meteor muss direkt vor dir sein |
| Es ruckelt auf einem alten Handy | In Roblox: Menü → Einstellungen → Grafikqualität etwas runterstellen |

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
  Der Server bewegt keine Meteore: jeder Client rechnet die Position auf dem Laufband selbst aus.

## 📁 Dateien

```
roblox-meteor-heist/
├── MeteorHeist.rbxlx          ← diese Datei in Studio öffnen
├── ANLEITUNG.md               ← du bist hier
├── default.project.json       ← für Rojo (Weg C)
└── src/
    ├── shared/   (ReplicatedStorage.Shared)
    │   ├── Config.luau        ← ALLE Einstellungen
    │   ├── Aliens.luau        ← alle 96 Aliens (3 pro Meteor)
    │   └── Util.luau
    ├── server/   (ServerScriptService.Server)
    │   ├── Main.server.luau
    │   └── Services/          Data, Graphics, Plot + MapBuilder, Meteor, Carry, Economy, Treadmill,
    │                          Monetization, Admin, Leaderboard, MeteorFactory, AlienFactory …
    └── client/   (StarterPlayerScripts.Client)
        ├── Main.client.luau   ← startet die Oberfläche
        └── Modules/           UI, Hud, Windows, Effects, WorldFX, Prompts, Fly, PhotoMode, AdminPanel
```
