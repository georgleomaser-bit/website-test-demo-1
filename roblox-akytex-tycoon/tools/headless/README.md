# AKYTEX TYCOON · Headless-Roblox-Harness (Entwurf – Fundament)

Ein Roblox-Emulator in reinem Luau, der den echten Spiel-Code (Server **und** Client) ohne Roblox ausführt,
Laufzeitfehler mit `src/…:Zeile` meldet und später UI-Klicks, Request-Fuzzing und einen Welt-Export erlaubt.
Ziel: Jede gemeldete Spiel-Fehlermeldung ist ein **echter** Bug (keine Fehlalarme), und echte Bugs werden nicht
übersehen. Verbindliche Spezifikation: `aky3_harness_spec.md` (Scratchpad).

Stand dieses Entwurfs: **Fundament fertig** (API-Daten, Datentypen, Enums, Instanz-System, Signale, Scheduler,
Kontexte, Fehlererfassung, Script-Umgebungen + `require`, Selbsttest). Es fehlen noch: Services mit Verhalten
(Players, RunService, TweenService, DataStore, Remotes/Netzwerk …), Bundler, Szenarien, `run.py`, Berichte als
Dateien, Renderer.

## Aufruf

```bash
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad
cd roblox-akytex-tycoon
$SP/luau-build/luau tools/headless/selftest.luau        # Selbsttest -> "SELFTEST OK (n Prüfungen)"
python3 tools/headless/gen_api.py                        # api_data.luau neu erzeugen (+ Stichproben-Check)
python3 tools/headless/gen_api.py --check                # nur prüfen
```

Der Luau-CLI hat `loadstring`, `getfenv/setfenv`, `newproxy`, `os`, Datei-`require` (relativ zur Datei; in
`init.luau` heißt `@self/X` „Kind“, `./X` „Geschwister des Ordners“), aber **kein `io`**: Ausgaben laufen über
`print`; `Report.emit(name, text)` schreibt Blöcke zwischen `@@BEGIN name@@` / `@@END name@@` für einen
Python-Wrapper.

## Dateien

| Datei | Inhalt |
|---|---|
| `gen_api.py` | Generator: globalTypes.d.luau (Member/Klassen/Enums/Creatable/Services) + Full-API-Dump (Enum-Werte, float/int/double, ReadOnly, Yields, Sicherheit, von luau-lsp weggelassene skriptbare Member) + rbx-reflection-DB (Defaults) + creator-docs (BrickColor-Tabelle, Font.fromEnum) |
| `api_data.luau` | erzeugt, committet (941 Klassen, 649 Enums, Defaults) |
| `runtime/init.luau` | Loader `require("./tools/headless/runtime").boot(config)` + **interne API-Doku** |
| `runtime/Util.luau` | `raise` (Fehler mit Spiel-Position), Argument-Prüfungen, `typeof`/`type`, float32, Formatierung |
| `runtime/Report.luau` | Fehler/Warnungen/Infinite-Yields/unmocked/deprecated sammeln, deduplizieren, rendern |
| `runtime/Scheduler.luau` | simulierte Zeit, Frame-Phasen, Threads, Kontexte, Deferred-Queue, `task.*`, alte `wait/spawn/delay` |
| `runtime/Signal.luau` | RBXScriptSignal/Connection (Deferred) |
| `runtime/Enum.luau` | Enum-System |
| `runtime/Datatypes/*` | Vector3/2(+int16), CFrame, Color3/BrickColor/ColorSequence, UDim/UDim2/Rect/Font/Content, NumberRange/NumberSequence/TweenInfo/Ray/Region3/PhysicalProperties/Axes/Faces/PathWaypoint/RaycastParams/OverlapParams/RaycastResult/CatalogSearchParams/SharedTable, DateTime/Random, JSON |
| `runtime/Instance/init.luau` | Instanz-Kern: Klassen-Records, Properties, Baum, Events, Attribute, Tags, Clone/Destroy, WaitForChild |
| `runtime/Instance/BasePart.luau` | BasePart/PVInstance/Model, Gelenke (WeldConstraint, Weld/Motor6D) |
| `runtime/Instance/Gui.luau` | AbsoluteSize/-Position, Layouts, TextBounds, ScrollingFrame, TextBox-Fokus |
| `runtime/Instance/DataModel.luau` | DataModel, `GetService`, Standard-Services, Workspace-Grundlagen, CollectionService |
| `runtime/Globals.luau` | Script-Umgebungen je Kontext, `require` (Cache je Kontext), `startScript` |
| `selftest.luau` | Selbsttest (Datentyp-Mathematik, Instanz-Fehler, Deferred-Signale, WaitForChild-Warnung, require …) |

## Interne API (Kurzfassung – Details im Kopf von `runtime/init.luau`)

```lua
local R = require("./tools/headless/runtime").boot({ frameRate = 30, startUnix = 1791972000, seed = 1 })
local server = R.Sched.newContext({ kind = "server", name = "server" })
local game = R.Inst.newDataModel({ name = "AkytexTycoon", creatorId = 1, placeId = 1, context = server })
server.game = game
R.Inst.setScriptSource(scriptInst, source, "src/server/Main.server.luau")   -- Bundler
R.Globals.startScript(server, scriptInst, source, "src/server/Main.server.luau")
R.Sched.run(10)                    -- 10 s simulieren (30 Hz)
print(R.Report.renderText())
```

* **Kontexte:** Jeder Thread trägt einen Kontext (`R.Sched.ctx()`); neue Threads (task.*, Signal-Handler,
  `coroutine.create/wrap`) erben den Kontext des Erzeugers bzw. des **verbindenden** Threads. `_G`, `shared` und der
  `require`-Cache sind je Kontext getrennt (wie getrennte VMs). `RunService:IsServer/IsClient` und
  `Players.LocalPlayer` sollen `R.Sched.ctx()` auswerten.
* **Fehler:** `R.Util.raise(msg)` für Roblox-artige API-Fehler (Position = aufrufende Spiel-Zeile, Kategorie A).
  Unbehandelte Fehler in Spiel-Threads landen automatisch per `xpcall`-Traceback in `R.Report.error` (dedupliziert
  nach Nachricht + erster `src/…`-Position, mit Zähler und Auslöser via `R.Report.setTrigger`). Abstürze im Harness
  selbst (oberster Frame im Harness, nicht per `raise`) werden als Kategorie B markiert. Fehler nach einem
  unmocked-Stub im selben Thread bekommen einen Hinweis.
* **Klassenverhalten / Services:** `R.Inst.define(class, spec)` bzw. `R.Inst.registerService(class, spec + setup)`
  mit `methods`, `props` (get/set), `callbacks` (onSet), `init`, `onChanged`, `onAncestry`, `postClone`,
  `onDestroy`, `signalOpts`. Nur laut API existierende Member (sonst Harness-Fehler). Nicht implementierte Methoden
  sind Stubs (geben nil zurück, Eintrag „unmocked“); nicht existierende Member werfen wie Roblox.
* **Frame-Phasen:** `network → input → render → legacyWait → preAnimation → preSimulation → physics →
  postSimulation → timers → late`; `R.Sched.addHook(phase, fn, name)`. RunService soll in `render`
  (RenderStepped/PreRender, nur Client), `preSimulation` (Stepped/PreSimulation) und `postSimulation`
  (Heartbeat/PostSimulation) feuern.
* **Beobachter:** `R.Inst.observe("created"|"changed"|"reparented"|"destroying"|"attribute"|"tag", fn)` – Basis
  für Replikation, Streaming, Welt-Export.
* **Harness-Helfer:** `Inst.create` (ohne creatable-Prüfung), `Inst.setProp` (typgeprüft, ohne read only),
  `Inst.rawSet`, `Inst.fire(inst, "Event", …)`, `Inst.callback(inst, "OnServerInvoke")`,
  `Inst.closeCallbacks(game)`, `Inst.setLoaded(game)` (feuert `game.Loaded`; Server sofort, Client nach der
  Erst-Replikation aufrufen), `Inst.Parts.simulateTouch(a, b)`, `Inst.Gui.isRendered(gui)`,
  `R.Sched.invoke(ctx, fn, …)` + `R.Sched.await(h)`, `R.Sched.callNoYield(fn, …)` (UpdateAsync-Transform,
  OnIncomingMessage).

### Empfehlung Server/Client-Modell (für den nächsten Schritt)

Das Fundament unterstützt beide Varianten der Spezifikation:

1. **Getrennte DataModels je Kontext + Replikator (empfohlen):** Server-Baum ist maßgeblich; ein Replikator
   (über `Inst.observe`) spiegelt Erzeugen/Property-/Attribut-/Tag-Änderungen/Parent-Wechsel/Destroy replizierter
   Container mit 1 Frame Latenz in den Client-Baum; Client-Änderungen bleiben lokal (außer eigener Figur).
   Remote-Argumente bilden Instanzen über eine Replikations-ID ab (nicht replizierte -> nil, wie Roblox). Vorteil:
   Client-Code, der Server-Teile lokal zerstört/verändert oder eigene Teile in Workspace legt, erzeugt **keine**
   Fehlalarme auf dem Server; ServerScriptService/ServerStorage sind auf dem Client automatisch leer; Streaming
   = Replikator lässt ferne Teile weg.
2. **Gemeinsamer Baum + `Inst.setVisibilityFilter(fn(inst, ctx))`:** einfacher, aber Client-Schreibzugriffe auf
   Server-Instanzen wirken dann auch auf dem Server (mögliche Fehlalarme bzw. übersehene Bugs).

## Treue-Entscheidungen

* Datentypen sind `newproxy`-userdata mit eigener Metatabelle (Daten liegen darin). `typeof` erkennt sie über
  registrierte `__index`-Funktionen (Luau-`typeof` ignoriert `__type` bei newproxy). In der Spiel-Umgebung liefert
  `type(Vector3)` wie in Roblox **"vector"**, `getmetatable` von Roblox-Objekten `"The metatable is locked"`.
* Vector3 wird als nativer Luau-`vector` gespeichert (float32 wie Roblox) und **interniert**: gleiche Vector3 sind
  rawequal und als Tabellenschlüssel gleichwertig (in Roblox ist Vector3 ein Werttyp). CFrame/Color3/UDim/Vector2
  sind float32-gerundet, UDim-Offsets int32. Float-Properties werden auf float32 gerundet
  (`part.Transparency = 0.1` liefert 0.10000000149…), int-Properties abgeschnitten.
* CFrame-Algorithmen nach G3D (Euler-Zerlegung, Achse/Winkel, `lookAt` mit Up-Wechsel und NaN bei Nullrichtung),
  `Lerp` = Quaternion-Slerp.
* Signale verhalten sich **Deferred** (Handler in eigenem Thread beim nächsten Resumption-Punkt, Disconnect vor
  Ausführung verhindert den Aufruf, `Once` trennt beim Feuern); `Destroying` läuft sofort; `Destroy` trennt alle
  Verbindungen. ValueBase.Changed liefert den neuen Wert (nur für `Value`).
* Property-Changed feuert nur bei echter Änderung; CFrame-Zuweisung meldet auch Position/Orientation/Rotation.
* `WaitForChild`: kein Yield, wenn vorhanden; erkennt Umbenennungen; Timeout -> nil; ohne Timeout nach 5 s
  simulierter Zeit Warnung `Infinite yield possible on 'X:WaitForChild("Y")'` mit Traceback des wartenden Threads.
* `Model.PrimaryPart` darf vor dem Parenten gesetzt werden und wird im nächsten Schritt auf nil gesetzt, wenn das
  Teil kein Nachfahre ist (Roblox-Legacy-Verhalten laut Doku). `WorldPivot` = Box-Mitte bis zum ersten Setzen.
* Gelenke wirken nur in Workspace: `part.CFrame = …` bewegt die Baugruppe, `part.Position = …` nur das Teil
  (WeldConstraint-Doku); Weld/Motor6D rasten auf `Part0 * C0 * Transform * C1:Inverse()` ein; verankerte Teile
  werden nie verschoben.
* `os.date` ohne `!` liefert auf dem **Server UTC** (Roblox-Server), auf dem Client die Prozess-Zeitzone (`TZ`).

## Bekannte Grenzen (Fundament)

* Keine Physik (kein Fallen, keine Kollisionen; `Touched` nur über `Inst.Parts.simulateTouch`).
* GUI-Geometrie grob: `AutomaticSize`, `UITextSizeConstraint`, Rich-Text-Breiten, Schriftmetriken sind Näherungen.
* `Random` ist deterministisch, aber nicht Roblox' exakte PCG32-Folge.
* Mehrdeutige Roblox-Fehlertexte sind sinngemäß nachgebildet (Fehler entsteht immer, Wortlaut kann abweichen).
* Unmocked-Stubs geben nil zurück (Folgefehler werden im Report mit Hinweis markiert).
* Vector3 ist in Roblox ein nativer `vector`; hier userdata – Spiel-Code mit `vector.*`-Bibliothek würde nicht
  mit Vector3 zusammenpassen (das Spiel nutzt sie nicht).
* Noch nicht vorhanden: Services mit Verhalten, Netzwerk/Remotes, Spieler/Figuren, Streaming, Bundler,
  Szenarien, Berichtsdateien.
