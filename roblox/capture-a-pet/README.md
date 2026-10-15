# Capture a Pet 🐾

Roblox-Spiel: Laufbänder trainieren, die Canyon-Strecke runterrennen, Tiere fangen, Eier aus Wächter-Nestern klauen, Tiere aus fremden Basen stehlen und mit Tieren Geld verdienen.

## Schnellstart (ohne Programmieren)

1. **Roblox Studio** installieren und einloggen.
2. Die Datei **`CaptureAPet.rbxl`** aus diesem Ordner herunterladen und doppelklicken (oder in Studio: *Datei → Öffnen*).
3. Oben auf **Play** drücken. Die ganze Map wird beim Start automatisch gebaut.
4. Damit gespeichert wird: *Datei → Bei Roblox veröffentlichen*, dann *Home → Game Settings → Security → „Enable Studio Access to API Services“* anschalten.
5. In *Game Settings → Places* (bzw. auf der Experience-Seite im Creator Dashboard) **Max Players auf 6** stellen, weil es 6 Basen gibt.

> In Studio bist du automatisch Admin. Im echten Spiel ist der Besitzer des Spiels (oder der Gruppe) Admin. Weitere Admins: UserIds in `src/shared/Config/Game.lua` bei `Game.AdminUserIds` eintragen.

## Robux einrichten (Gamepässe und Produkte)

Alle IDs stehen noch auf `0`. Dann zeigt das Spiel „coming soon“ an und man kann nichts kaufen.

1. Creator Dashboard → deine Experience → **Monetization → Passes**: diese 6 Pässe anlegen:
   `2x Cash`, `2x Training`, `Fast Hatch`, `VIP`, `Lucky`, `Bait Bag`
2. **Monetization → Developer Products**: diese 9 Produkte anlegen:
   `Cash Pile`, `Cash Stack`, `Cash Vault`, `x2 Speed (15 min)`, `x2 Cash (15 min)`, `x2 Luck (15 min)`, `Server Luck x2 (10 min)`, `5 Glow Baits`, `Hatch All Now`
3. Die IDs in **`src/shared/Config/Monetization.lua`** bei `Id = 0` eintragen (Preise dort sind nur Anzeige, der echte Preis kommt vom Dashboard).

Jeder Kauf wird genau einmal gutgeschrieben (Kauf-ID wird gespeichert, erst nach dem Speichern wird der Kauf bestätigt). Es gibt **keine bezahlten Zufalls-Eier**, deshalb musst du keine Odds anzeigen.

## Mit Rojo weiterentwickeln (optional)

Wenn du den Code in VS Code bearbeiten willst:

1. [Rojo](https://rojo.space) installieren (VS Code Extension „Rojo“ + Studio-Plugin).
2. In diesem Ordner `rojo serve` starten, in Studio im Rojo-Plugin auf **Connect** klicken.
3. Neue Place-Datei bauen: `rojo build default.project.json -o CaptureAPet.rbxl`

## Was steckt drin

| System | Wo einstellen |
| --- | --- |
| 40 Tiere in 4 Zonen (Common bis Secret), Gewicht, Mutationen (Golden, Diamond, Rainbow) | `Config/Animals.lua`, `Config/Game.lua` |
| 4 Zonen: Sunny Meadow, Red Canyon, Frost Peaks, Lava Rift | `Config/Zones.lua` |
| 8 Laufbänder + VIP-Laufband pro Base | `Config/Treadmills.lua` |
| Upgrades: Cash, Training, Luck, Hatch Speed je bis **x1000**, dazu Pen Slots und Incubators | `Config/Upgrades.lua` |
| Wächter-Nester mit Eiern, Wild-Aura (je länger du entkommst, desto stärker), Leuchtköder | `Config/Game.lua` |
| Seltene Eier (ab Rare) mit Aura-Ring, Legendary+ mit Krone | `Game.EggAuraMinRarity` |
| Klauen aus fremden Basen mit Alarm, Base-Lock, Schutz für neue Spieler/Tiere | `Config/Game.lua` (Steal…) |
| Reiten: jedes Tier als Reittier, Tempo nach Seltenheit und Aura | `Game.MountSpeed` |
| Dragon Lair Event alle 12 Minuten für 3 Minuten | `Game.Lair…` |
| Rebirths, Daily Login (7 Tage), Playtime-Geschenke, 3 Tagesaufgaben, Expeditionen, Codes, Index-Belohnungen | `Config/Rewards.lua` |
| Friend Boost (+10 % pro Freund), Offline-Einkommen, globale Bestenlisten | `Config/Game.lua` |
| Admin Panel (Taste **F2** oder 🛠-Button) | `Server/Services/AdminService.lua` |

**Codes zum Testen:** `RELEASE`, `SPEED`, `LUCKY`, `TAMER`

## Steuerung

- **E halten**: Tier fangen, Ei klauen, Tier klauen, Laufband kaufen, Ei schlüpfen lassen
- **1 / G**: Leuchtköder werfen (zur Maus bzw. nach vorne)
- **2 / R**: Reiten an/aus (nimmt dein schnellstes Tier)
- **3 / Q**: Getragenes fallen lassen
- **4**: Base abschließen
- **F2**: Admin Panel

## Eigene Tier-Modelle

Die Tiere werden aus Blöcken gebaut. Willst du ein eigenes Modell: Modell in Studio unter `ReplicatedStorage` in einen Ordner **`AnimalModels`** legen und genau wie das Tier benennen (z. B. `Oni Tiger`). Dann wird automatisch dein Modell benutzt.

## Hinweis

Der Code ist gelintet und baut sauber, aber getestet werden kann er nur in Roblox Studio. Wenn dir beim Testen irgendwas komisch vorkommt: Fehlermeldung aus dem Output-Fenster kopieren und schicken.
