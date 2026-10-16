# 🍋 Zitronen-Fabrik Tycoon (Roblox)

Ein **Förderband-Tycoon** im **klassischen Roblox-Block-Stil** (Plastik-Blöcke mit Noppen, Standardfarben, Standard-Schrift) – inspiriert vom Trend-Spiel **Sell Lemons**: klein anfangen mit 1 $ von Papa, Zitronen pressen, Linie um Linie bauen, Manager einstellen, bei **Zorp dem Alien** Rebirth machen und die Früchte per **Evolution** verwandeln.

> Alles ist eigener Code und eigene Namen – es werden keine Inhalte aus Sell Lemons kopiert.

## So startest du das Spiel

1. **Roblox Studio** öffnen → **Datei → Öffnen** → `build/ZitronenFabrikTycoon.rbxl` auswählen.
   Du siehst sofort die Insel mit Lobby, Obby-Baum, Zorps UFO, Portal und den 6 Fabriken.
2. Oben auf **▶ Play** (F5) drücken – fertig. Du startest in deiner eigenen Fabrik.
3. **Speichern einschalten:** Spiel einmal veröffentlichen (**Datei → In Roblox veröffentlichen**), dann
   **Game Settings → Security → „Enable Studio Access to API Services“** anschalten.
   Ohne das läuft alles, es wird nur nicht gespeichert (das Spiel sagt dir das auch).
4. **Maximale Spieler auf 6 stellen:** Game Settings → Places → Max Players = **6** (es gibt 6 Fabriken).
5. Optional: **Test-Menü** 🛠️ (Knopf links, nur in Studio sichtbar) gibt dir Geld, Investoren, startet Events usw. – so kannst du alles schnell ausprobieren.

## Was steckt drin?

**Fabrik & Förderbänder**
- 6 Linien mit eigenem Gebäude: 🍋 Zitronen-Stand · 🚚 Limo-Lieferdienst · 🏭 Saft-Depot · 🧪 Zitronen-Labor · 📈 Zitronen-Börse · 🛸 Weltraum-Plantage
- Früchte fallen aus der Maschine, fahren sichtbar übers Band, **verwandeln sich unter jedem Maschinen-Bogen** (z. B. Zitrone → gewaschen → Limo-Becher → Eis-Limo) und plumpsen in den Verkaufs-Trichter (+$-Anzeige)
- Klassische **Kauf-Knöpfe** zum Drauftreten (grün = bezahlbar, rot = zu teuer) und ein **gelber Pfeil** zum nächsten Kauf
- Ohne Manager: den **roten Knopf** drücken. Mit **Manager** (NPCs mit Brainrot-Style-Namen wie *Limonino Spremitore*) läuft die Linie von allein – auch offline
- **Level** bis 1000 mit **Meilensteinen** (2× Tempo bei Level 25, 50, 100 …), Kaufmenge ×1/×10/×100/MAX
- 3 **Maschinen-Bögen** pro Linie (×2, ×3, ×5) und 6 **Deko**-Stufen (Zaun, Blumen, Laternen, Palmen, Brunnen, Riesen-Zitrone)

**Fortschritt**
- 64 **Geld-Upgrades** (×3 für eine Linie, ×3 für alles, stärkere Investoren) mit „Alle kaufen“
- **Rebirth bei Zorp dem Alien** 🛸: Alien-Investoren (+2 % pro Investor) – wie bei Sell Lemons
- 7 **Alien-Kräfte** (Turbo-Bänder, Startgeld, goldene Zitronen ×10, Rabatte, Offline-Bonus …) – kosten Investoren
- **Frucht-Evolution** im lila Portal 🌀: Zitrone → Orange → Limette → Drachenfrucht → Sternfrucht → Galaxie-Frucht (×5 Geld und ×2 Tempo pro Stufe, alle Früchte auf den Bändern verwandeln sich)

**Welt & Geheimnisse**
- **Obby-Zitronenbaum** in der Mitte: hochklettern, goldene Zitrone pflücken (1× am Tag)
- **Kanalisation** 🕳️ unter dem Kanaldeckel: Labyrinth mit 4 farbigen Hebeln, Hinweis auf dem Wandbild (Reihenfolge wird pro Server ausgewürfelt) → Tresor → **UFO-Schlüssel** → zu Zorp bringen = Investoren für immer 50 % stärker
- **Server-Events** alle 6–9 Minuten: ⚡ Turbo-Zeit, 💸 Geldregen (×3), 🍋 Zitronen-Regen (goldene Zitronen einsammeln)
- **Bestenliste** „Reichste Fabriken“ auf dem Platz, **tägliche Belohnung** mit 7-Tage-Serie, **Offline-Geld**
- Speichern mit DataStores, Gamepässe/Dev-Produkte vorbereitet

## Anpassen

Fast alles steht in **`src/shared/Config.luau`** (in Studio: `ReplicatedStorage → Shared → Config`):

| Was | Wo in Config |
|---|---|
| Preise, Einnahmen, Tempo der Linien | `Config.Lanes` |
| Namen der Maschinen & Manager | `Config.Lanes[...].Upgraders` / `.Manager` |
| Upgrades, Deko, Alien-Kräfte | `Config.CashUpgradeSettings`, `Config.Decor`, `Config.Powers` |
| Rebirth & Evolution | `Config.Rebirth`, `Config.Evolution` |
| Events | `Config.Events` |
| Gamepässe / Dev-Produkte | `Config.GamePasses`, `Config.DevProducts` – **ID eintragen** (0 = aus, dann ist der Shop versteckt) |
| Sounds & Musik | `Config.Sounds` (eingebaute Roblox-Sounds, durch Creator-Store-IDs ersetzbar; Musik ist leer) |
| Admins fürs Test-Menü | `Config.AdminUserIds` |

**Welt neu bauen:** Die Welt liegt fertig in `Workspace → World`. Löschst du den Ordner `World`, baut das Spiel ihn beim nächsten Start automatisch neu aus dem Code.

## Projekt-Aufbau

```
roblox-zitronen-fabrik/
├─ default.project.json        Rojo-Projekt
├─ build/ZitronenFabrikTycoon.rbxl   fertige Place-Datei für Roblox Studio
├─ src/shared/                 Config, Economy (alle Formeln), Format, Remotes
├─ src/server/                 Main + World (Bau der Welt) + Services (Spiel-Logik)
├─ src/client/                 HUD, Fenster, Förderband-Animation, Effekte
├─ tests/                      Tests + Balance-Simulation (laufen mit Lune)
└─ tools/                      build.sh, bake.luau
```

## Für Entwickler

Mit [Rojo](https://rojo.space) kannst du live aus VS Code nach Studio synchronisieren: `rojo serve` und im Studio-Plugin verbinden.
Die Place-Datei baut `tools/build.sh` (braucht `rojo` und [`lune`](https://lune-org.github.io)): Rojo-Build → Tests → Welt „backen“.

- `tests/shared.test.luau` – Zahlenformat & Wirtschaftsformeln
- `tests/world.test.luau` – baut die komplette Welt und eine voll ausgebaute Fabrik, prüft Positionen, Knöpfe und das Labyrinth
- `tests/balance.sim.luau` – simuliert einen Spieler (erst `rojo build default.project.json -o build/_rojo.rbxlx`, dann `lune run tests/balance.sim.luau build/_rojo.rbxlx 6`)

Balance laut Simulation (geschickter Spieler): alle 6 Linien nach ~20 Min, erster Rebirth nach ~35 Min, erste Evolution nach ~4 Std.
