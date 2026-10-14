# AKYTEX TYCOON · Headless-Roblox-Harness

Ein Roblox-Emulator in reinem Luau, der den echten Spiel-Code (Server **und** Client, alle 148 Skripte aus
`default.project.json`) ohne Roblox ausführt und Laufzeitfehler mit `src/…:Zeile` meldet.
Ziel: Jede gemeldete Spiel-Fehlermeldung ist ein **echter** Bug (keine Fehlalarme), und echte Bugs werden nicht
übersehen. Verbindliche Spezifikation: `aky3_harness_spec.md` (Scratchpad). Spiel-Bugs werden nur **gemeldet** –
der Harness ändert nie etwas unter `src/`.

## Schnellstart

```bash
cd roblox-akytex-tycoon
python3 tools/headless/run.py boot                       # Besitzer-Client, Live-Modus, 120 s simuliert
python3 tools/headless/run.py boot --client 2            # Client des normalen Spielers
python3 tools/headless/run.py boot --studio              # RunService:IsStudio() = true (SelfTests laufen)
python3 tools/headless/run.py boot --client 2 --studio --out boot-p2-studio
```

Ergebnis: Kurzfassung auf stdout, Berichte unter `tools/headless/out/` (bzw. `out/<--out>/`).
Exit-Code 0 = Szenario lief durch (auch wenn Spiel-Bugs gefunden wurden), 2 = Harness-Absturz.
Laufzeit: Live ca. 25–35 s, Studio ca. 60–70 s (SelfTests rechnen viel Marktgeschichte) für 120 s Spielzeit.

Selbsttests des Harness:

```bash
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad
$SP/luau-build/luau tools/headless/selftest.luau           # Fundament  -> "SELFTEST OK (326 Prüfungen)"
$SP/luau-build/luau tools/headless/selftest_services.luau  # Services/Netz -> "SELFTEST-SERVICES OK (62 Prüfungen)"
python3 tools/headless/gen_api.py --check                  # API-Daten prüfen (neu erzeugen: ohne --check)
```

Der Luau-CLI-Pfad kann mit `--luau PFAD` oder der Umgebungsvariable `LUAU` überschrieben werden.

## Optionen von `run.py`

| Option | Bedeutung |
|---|---|
| `boot` | Szenario (derzeit nur `boot`) |
| `--client 1\|2` | welcher Spieler einen Client-Kontext bekommt: 1 = Besitzer (UserId = `game.CreatorId`, de-de, Premium), 2 = normaler Spieler (en-us). Der andere Spieler existiert nur serverseitig. |
| `--studio` / `--live` | `RunService:IsStudio()`; Standard `--live` |
| `--seconds N` | simulierte Spielzeit (Standard 120) |
| `--seed N` | Zufalls-Seed (`math.random`, `Random.new()` ohne Seed, GUIDs) |
| `--echo` | Fehler und Ausgaben sofort auf stdout |
| `--no-streaming` | Instanz-Streaming aus (Standard: wie `Workspace.StreamingEnabled` aus dem Projekt) |
| `--faults "ds=1,mem=1,msg=1,http=1"` | Fehler-Injektion: die ersten n Aufrufe je Dienst-Art schlagen mit typischem Roblox-Fehler fehl (Live-Server-Störung) |
| `--no-bundle` | `out/bundle.luau` nicht neu bauen |
| `--out DIR` | Berichte nach `out/DIR/` |
| `--timeout S` | Abbruch des Luau-Prozesses (Standard 900 s) |

## Szenario `boot`

1. Server-DataModel bauen (Rojo-Sourcemap + `$properties`/`$attributes`), Server-Skripte in
   ServerScriptService/Workspace starten (alle Services Init/Start).
2. Nach 1 s tritt **AkyOwner** (Besitzer) bei, nach weiteren 0,5 s **Spieler2**. Für den gewählten Spieler
   läuft ein vollständiger Client: Erst-Replikation (Phase A: Players + eigener Player + ReplicatedFirst,
   Phase B einen Frame später: restliche replizierte Services, `game.Loaded`), PlayerScripts aus
   StarterPlayerScripts, StarterGui-Kopie, Figur mit StarterCharacterScripts.
3. Prüfungen: `Server gestartet`, `Markt läuft`, Config-Validierung, SelfTest-Ergebnis (nur Studio),
   Client-UI (`AkytexTycoonUI`, Hud sichtbar, TRADE-Knopf sichtbar), Figur repliziert, Klick auf TRADE
   (öffnet das Terminal; neu sichtbare GUI-Objekte werden gezählt).

## Berichte (`tools/headless/out/…`)

| Datei | Inhalt |
|---|---|
| `report.txt` | Hauptbericht (Abschnitte siehe unten) |
| `report.json` | dieselben Daten maschinenlesbar |
| `output.txt` | alle `print`/`warn`-Ausgaben des Spiels (Server + Client, mit Zeit und Kontext) |
| `ui_tree.txt` | GUI-Baum des Clients mit AbsolutePosition/-Size, Sichtbarkeit, Texten |
| `ui_tree_trade.txt` | GUI-Baum nach dem Klick auf TRADE |
| `harness_crash.txt` | nur bei Absturz des Harness selbst |
| `bundle.luau` | Bündel aller Skripte (von `bundle.py`, nicht committen) |

Abschnitte von `report.txt`:

* **ZUSAMMENFASSUNG / PRÜFUNGEN** – Zähler und Szenario-Prüfungen (`[OK]`/`[FEHLT]`).
* **(A) Unbehandelte Laufzeitfehler** – Fehler, die einen Spiel-Thread beendet haben, mit Traceback
  (`src/…:Zeile`), Auslöser (Remote/Signal/Skriptstart) und Zähler. Das sind Spiel-Bugs.
* **(A) Abgefangene Laufzeit-/API-Fehler** – Fehler in `pcall`/`xpcall` des Spiels, die auf einen Bug hindeuten
  (Indexfehler, falsche API-Nutzung, `X is not a valid member …`). Das Spiel läuft weiter, aber das Feature
  funktioniert nicht.
* **Spiel-Warnungen / Infinite-Yields** – `warn()` des Spiels und `WaitForChild` ohne Timeout nach 5 s.
* **Harness-Hinweise** – Roblox-Verhalten, das Daten still verändert (Remote-Tabellen mit gemischten Schlüsseln,
  Funktionen in Remote-Argumenten, DataStore-Warteschlange, Unreliable > 900 Byte …).
* **(B) Harness-Verdacht** – Fehler, deren oberster Frame im Harness liegt (kein Spiel-Bug, Harness verbessern).
* **Unmocked / Deprecated APIs** – laut API vorhandene, im Harness nur als Stub (nil) umgesetzte Member;
  veraltete APIs mit Fundstellen.
* **Injizierte Dienst-Fehler** (nur mit `--faults`) – per Fehler-Injektion ausgelöste DataStore-/MemoryStore-/
  Messaging-Fehler, die das Spiel abgefangen hat (Info; die Reaktion des Spiels steht in den Warnungen/Prüfungen).
  Unbehandelte Folgefehler einer Injektion erscheinen dagegen in (A): Das Spiel verträgt die Störung nicht.
* **Vom Spiel geworfene, abgefangene Fehler** – `error()` im Spiel-Code, die das Spiel selbst abfängt (Info).

## Dateien

| Datei | Inhalt |
|---|---|
| `bundle.py` | Bundler: `rojo sourcemap` + `default.project.json` (`$properties`, `$attributes`, `$className`) -> `out/bundle.luau` (Baum + Quelltexte als Long-Strings) |
| `run.py` / `run.luau` | Einstieg: Bündel bauen, Luau-CLI starten, Marker-Blöcke `@@BEGIN name@@ … @@END name@@` in Dateien zerlegen |
| `gen_api.py` / `api_data.luau` | API-Daten (Klassen, Member, Enums, Defaults, Sicherheit, Yields) aus luau-lsp-Typen + Full-API-Dump + rbx-reflection |
| `runtime/init.luau` | Loader `require("./tools/headless/runtime").boot(config)` + interne API-Doku |
| `runtime/Util.luau`, `Report.luau`, `Scheduler.luau`, `Signal.luau`, `Enum.luau` | Fehler mit Spiel-Position, Fehlererfassung, simulierte Zeit/Frame-Phasen/Threads/Kontexte, Deferred-Signale, Enums |
| `runtime/Datatypes/*` | alle Roblox-Datentypen (Vector3, CFrame, Color3, UDim2, TweenInfo, Ray, Region3, DateTime, Random, JSON …) |
| `runtime/Instance/*` | Instanz-Kern, BasePart/Model/Gelenke, GUI-Geometrie (inkl. UIScale), DataModel/CollectionService |
| `runtime/Globals.luau` | Script-Umgebungen je Kontext, `require` mit Cache je Kontext, `pcall`-Erfassung, `os.clock`/`tick` |
| `runtime/Services/init.luau` | Service-Helfer, Fehler-Injektion, RunService |
| `runtime/Services/Players.luau` | Players/Player/Figuren (R15-Rig), Humanoid, Sitze, Animator, Ban-API |
| `runtime/Services/World.luau` | Workspace-Abfragen (Raycast/Shapecast/GetPartBounds…), Kollisionsgruppen, Terrain, Kamera |
| `runtime/Services/Tween.luau` | TweenService (Validierung, Easing, Wiederholung), Debris |
| `runtime/Services/Input.luau` | UserInputService, ContextActionService, GuiService, StarterGui:SetCore, GUI-Klicks |
| `runtime/Services/Data.luau` | DataStore (Validierung, Budgets, 6-s-Schreibsperre), OrderedDataStore, MemoryStore, MessagingService |
| `runtime/Services/Platform.luau` | Marketplace, Policy, Badge, Group, Social, Localization, Analytics, HttpService … |
| `runtime/Services/Text.luau` | TextService, TextChatService (Kanäle, Befehle, Callbacks), Chat |
| `runtime/Services/Misc.luau` | ContentProvider, ProximityPrompt, ClickDetector, Sound, Lighting, Teams, Pathfinding, LogService, ScriptContext, Bindables, UserSettings, Path2D … |
| `runtime/Net.luau` | Replikator, Remotes, Streaming |
| `runtime/Game.luau` | DataModels aus dem Bündel bauen, Spieler beitreten/verlassen lassen, Shutdown |
| `runtime/Scenarios.luau` | Szenarien, Prüfungen, Berichte |
| `selftest.luau`, `selftest_services.luau` | Selbsttests |

## Architektur und Treue-Entscheidungen

### Server/Client: getrennte DataModels + Replikator (bewusste Abweichung)

Die Spezifikation beschreibt einen gemeinsamen Baum mit Sichtbarkeitsfilter. Umgesetzt ist stattdessen ein
**eigenes DataModel je Kontext** (Server + je Client) in **einer** Luau-VM mit einem Replikator. Grund: In Roblox
bleiben Client-Änderungen lokal. Mit einem gemeinsamen Baum würden Client-Skripte, die Server-Teile verändern
oder zerstören, auf dem Server wirken (Fehlalarme bzw. übersehene Bugs). Folgen:

* ServerScriptService/ServerStorage sind auf dem Client leer; `_G`, `shared` und `require`-Caches sind je
  Kontext getrennt (wie getrennte VMs).
* Replikation über **eine geordnete Nachrichten-Warteschlange je Client** (Teilbaum-Schnappschüsse,
  Property/Name/Attribut/Tag/Parent/Destroy/Pivot, Remote-Events, Invokes, Antworten), angewendet in der
  `network`-Phase des **nächsten** Frames (ein Frame Latenz, Reihenfolge wie gesendet). `InvokeServer` braucht
  damit mindestens zwei Frames hin und zurück.
* Neue Teilbäume kommen atomar an; Instanz-Referenzen auf noch nicht replizierte Objekte werden nachgereicht.
* Eigene Figur: CFrame-Änderungen des Clients replizieren zum Server (Network-Ownership), sonst nichts.
* PlayerGui/Backpack nur für den Besitzer, StarterGear/PlayerScripts nie; Server-Kamera wird nicht repliziert.

### Remotes (Roblox-Serialisierung)

Tiefe Kopie; Metatabellen fallen weg; Funktionen/Threads -> nil (Bindables behalten sie); Instanzen nur, wenn
beim Empfänger repliziert (sonst nil); gemischte/lückenhafte Tabellen -> nur Array-Teil (+ Hinweis);
Nicht-String-Schlüssel in Dictionaries -> `tostring` (+ Hinweis); zyklische Tabellen -> Fehler beim Sender;
UnreliableRemoteEvent > 900 Byte wird verworfen (+ Warnung). Events vor dem ersten `Connect` werden gepuffert
(Limit 256, danach „Remote event invocation queue exhausted“). Fehler in `OnServerInvoke` kommen beim
aufrufenden Client als Fehler an. Seitenprüfungen (`FireServer` nur Client usw.) wie in Roblox.

### Streaming

Bei `Workspace.StreamingEnabled` (aus dem Projekt) streamt der Replikator BaseParts und Modelle nach Abstand zur
Figur (StreamingTargetRadius/MinRadius aus den `$properties`, Opportunistic Stream-Out), `Persistent`/
`PersistentPerPlayer`-Modelle und die eigene Figur immer, nicht-räumliche Instanzen sofort; Pässe alle 0,25 s;
`RequestStreamAroundAsync` setzt einen temporären Fokus. Atomic-Modelle kommen als Ganzes, Legacy-Modelle
verhalten sich wie Nonatomic.

### Zeit

Simulierte Zeit mit 30 Hz und Frame-Phasen `network → input → render → legacyWait → preAnimation →
preSimulation → physics → postSimulation → timers → late`. `os.clock()`/`tick()` = simulierte Zeit + echte
Rechenzeit seit dem letzten Fortsetzen des laufenden Threads – so terminieren Zeitbudget-Schleifen des Spiels
(z. B. `CandleStore.Work`), und lange Rechenblöcke zählen wie in Roblox. `os.time`/`DateTime` laufen ab
Samstag 10.10.2026 17:59 Berlin. `os.date` ohne `!` liefert auf dem Server UTC.

### Fehlererfassung

* Unbehandelte Fehler in Spiel-Threads -> Report (dedupliziert nach Nachricht + erster `src/…`-Position).
* `pcall`/`xpcall` des Spiels sind umhüllt: abgefangene Fehler werden klassifiziert in *api* (Roblox-API-Fehler),
  *runtime* (Index-/Arithmetik-/Aufruffehler), *thrown* (`error()` des Spiels oder direkt von `pcall` gerufene
  Builtins – erwartet) und *harness* (oberster Frame im Harness).
* NotScriptable-Properties aus `$properties` (z. B. `BanningEnabled`, `StreamingTargetRadius`) sind für den
  Spiel-Code unsichtbar (Zugriff wirft wie in Roblox), werden aber vom Harness ausgewertet.

### Weitere Details (Fundament)

* Datentypen sind `newproxy`-userdata; `type(Vector3)` liefert wie in Roblox `"vector"`, `getmetatable` von
  Roblox-Objekten `"The metatable is locked"`. Vector3 wird interniert (gleiche Werte sind rawequal),
  float32-Rundung für CFrame/Color3/Float-Properties, int32 für UDim-Offsets.
* Signale verhalten sich **Deferred**; `Destroying` läuft sofort; `Destroy` trennt alle Verbindungen.
* `WaitForChild` ohne Timeout warnt nach 5 s simulierter Zeit (`Infinite yield possible on …`) mit Traceback.
* Gelenke (WeldConstraint/Weld/Motor6D) bewegen Baugruppen in Workspace; verankerte Teile werden nie verschoben.
* Nur laut API existierende Member; nicht existierende werfen wie Roblox, nicht implementierte sind Stubs
  (Eintrag „unmocked“, Folgefehler werden markiert).

## Bekannte Grenzen

* Keine Physik (kein Fallen, keine Kollisionen); `Touched` nur simuliert, Humanoid:MoveTo läuft geradlinig.
* GUI-Geometrie genähert: `AutomaticSize`, Schriftmetriken, Rich-Text-Breiten, `ClipsDescendants`.
* `Random` ist deterministisch, aber nicht Roblox' exakte PCG32-Folge.
* Einige Roblox-Fehlertexte sind sinngemäß nachgebildet (der Fehler entsteht immer, der Wortlaut kann abweichen).
* Replikation von Teilbäumen ist atomar (Roblox kann große Teilbäume aufteilen); Streaming vereinfacht
  (Abstand je Teil, kein Speicherdruck).
* `os.clock()` kann zwischen verschiedenen Threads minimal zurückspringen (Rechenzeit je Fortsetzung).
* Figur-Rig vereinfacht (R15-Teile/Motor6D, keine echten Animationen).
* Nur Desktop-Geräte (Maus/Tastatur, 1280×720); Touch/Gamepad/VR nur als Flags.
* MarketplaceService-Kaufdialoge enden immer „abgebrochen“; DataStores sind nur im Speicher.
* Noch nicht umgesetzt: Szenarien ui-crawl, prompt-crawl, request-fuzz, purchase, shutdown, world-Export,
  Renderer.
