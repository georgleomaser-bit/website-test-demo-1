# 🥚 Eier-Raub – Roblox-Spiel

Ein Roblox-Spiel nach dem „Klau-und-Basis“-Prinzip: Eier kaufen, Geld verdienen, bei anderen klauen und die eigene Basis verteidigen.
Dazu kommt eine eigene Wendung: **Eier müssen erst ausbrüten**, bevor sie etwas bringen.

Alles wird per Script gebaut: Map, Basen, Laufband, Bäume, Licht, Eier, Tiere und die Oberfläche.
Du brauchst keine Modelle aus der Toolbox.

## So funktioniert das Spiel

1. **Laufband:** Aus der Ei-Maschine rollen ständig zufällige Eier. Mit **E** kaufst du eins, und es läuft selbst zu deiner Basis.
2. **Ausbrüten (neu):** Ein gekauftes Ei steht auf deinem Brutplatz und wackelt, bis es schlüpft.
   Die Brutzeit hängt von der Seltenheit ab, von 10 Sekunden (Gewöhnlich) bis 5 Minuten (GEHEIM).
   Erst danach schlüpft ein **Tier**, und erst das Tier bringt Geld pro Sekunde.
3. **Überraschungs-Mutation:** Beim Schlüpfen wird gewürfelt, ob das Tier eine Mutation bekommt: Gold x2, Diamant x4 oder Regenbogen x10.
   Was rauskommt, sieht man vorher nicht.
4. **Geld einsammeln:** Das Geld sammelt sich vor jedem Platz auf der grünen **Kasse**. Drüberlaufen sammelt es ein.
5. **Klauen:** Halte **E** bei Eiern oder Tieren in fremden Basen.
   Du trägst die Beute über dem Kopf, bist dabei langsamer und musst sie in deine Basis bringen.
   Bei Eiern bleibt der Brutfortschritt erhalten.
6. **Verteidigen:** Jeder hat einen **Schläger**. Ein Treffer auf einen Dieb wirft ihn zurück, und die Beute fliegt zurück zum Besitzer.
7. **Sperren:** Der rote Knopf in deiner Basis sperrt sie für 60 Sekunden. Fremde werden dann rausgeworfen.
8. **Verkaufen:** Eigene Eier und Tiere kannst du für 50 % des Preises verkaufen.
9. **Speichern:** Geld, Eier, Tiere und Brutfortschritt werden automatisch gespeichert.

### Eier & Tiere

| Seltenheit | Eier → Tiere | Brutzeit |
|---|---|---|
| Gewöhnlich | Wachtelei → Wachtelküken, Hühnerei → Küken, Entenei → Entlein, Schoko-Ei → Schoko-Häschen | 10 s |
| Selten | Gänseei → Gössel, Straußenei → Straußenküken, Pinguin-Ei → Pinguinbaby | 20 s |
| Episch | Kristall-Ei → Kristallwurm, Lava-Ei → Lavasalamander, Frost-Ei → Frostfuchs | 40 s |
| Legendär | Goldenes Ei → Goldgans, Drachenei → Babydrache | 1:15 |
| Mythisch | Galaxie-Ei → Sternenwal, Regenbogen-Ei → Regenbogen-Einhorn | 2:00 |
| Göttlich | Kosmisches Ei → Kosmo-Phönix | 3:00 |
| GEHEIM | Schatten-Ei → Schattenkrähe | 5:00 |

Preise, Einkommen, Brutzeiten und Chancen stehen alle in `src/shared/Config.luau` und lassen sich dort leicht ändern.

## 🛠️ Admin-Panel

Admins sehen links den Knopf **🛠️ Admin**. Alternativ öffnet die Taste **P** das Panel.

- **👥 Spieler:** Geld geben oder setzen, Basis sperren oder entsperren, alle Eier sofort schlüpfen lassen.
  Außerdem: Basis leeren, Spielstand zurücksetzen, hinteleportieren, herholen, Tempo setzen und kicken.
- **🥚 Eier:** Jedes Ei mit jeder Mutation spawnen, aufs Laufband oder direkt in die Basis eines Spielers (auch schon geschlüpft).
  Laufband leeren, alle Eier auf dem Server schlüpfen lassen.
- **🎉 Events:** Glück x2 bis x25, Geld-Boost, schnelleres Brüten, Eierregen und Laufband-Tempo.
  Laufende Events sieht jeder oben im Bild.
- **📢 Durchsage:** Große Nachricht an alle Spieler, gefiltert durch den Roblox-Textfilter.

**Wer ist Admin?**
- Der Besitzer des Spiels, bei Gruppenspielen der Gruppen-Besitzer mit Rang 255.
- Alle UserIds, die du in `Config.Admins` einträgst.
- **In Roblox Studio jeder Spieler**, damit du alles testen kannst.

Jede Admin-Aktion wird auf dem Server geprüft. Ein normaler Spieler kann die Befehle nicht auslösen, auch nicht mit Exploits.

## Installation

### Variante A: Fertige Datei (am einfachsten)

1. `EierRaub.rbxlx` herunterladen.
2. In Roblox Studio öffnen: **Datei → Öffnen**.
3. **Play** (F5) drücken. Die Map baut sich beim Start automatisch.

### Variante B: Mit Rojo (für Entwickler)

```bash
cd roblox/eier-raub
rojo serve
```

Dann im Studio-Plugin von Rojo auf **Connect** klicken. Eine neue Place-Datei baust du mit `rojo build default.project.json -o EierRaub.rbxlx`.

### Variante C: Von Hand kopieren

1. In **ReplicatedStorage** einen Ordner `EierRaub` anlegen und darin ein **ModuleScript** `Config` erstellen.
   Inhalt: `src/shared/Config.luau`.
2. In **ServerScriptService** ein **Script** anlegen. Inhalt: `src/server/Main.server.luau`.
3. In **StarterPlayer → StarterPlayerScripts** ein **LocalScript** anlegen. Inhalt: `src/client/Main.client.luau`.

Das Script entfernt die Standard-`Baseplate` aus der Studio-Vorlage, weil sie sonst mit der Wiese flackert.

## Veröffentlichen

1. **Datei → In Roblox veröffentlichen**.
2. **Spieleinstellungen → Sicherheit → „Studio-Zugriff auf API-Dienste aktivieren“** einschalten.
   Ohne diese Einstellung funktioniert das Speichern in Studio nicht.
3. **Spieleinstellungen → Orte → Max. Spieler = 8**, denn es gibt 8 Basen.
4. Optional: **Lighting → Technology = Future** für die schönsten Lichter.

## Dateien

```
roblox/eier-raub/
├── default.project.json      Rojo-Projekt
├── EierRaub.rbxlx            fertige Place-Datei
└── src/
    ├── shared/Config.luau    Eier, Preise, Brutzeiten, Seltenheiten, Admins
    ├── server/Main.server.luau  Map, Basen, Laufband, Brüten, Klauen, Speichern, Admin-Befehle
    └── client/Main.client.luau  HUD, Meldungen, Admin-Panel, Animationen
```
