# AKYTEX TYCOON – Live-Ops-Plan (Wochenplan, Saisons, Events, Notschalter)

Diese Datei ist dein **Kalender als Besitzer**. Fast alles läuft **automatisch** auf allen Servern gleichzeitig.
Du musst nur zwei Dinge selbst tun: **samstags um 16:00 das Wochen-Update veröffentlichen** (wenn es eins gibt) und
**samstags um 18:00 Admin-Abuse** machen (freiwillig – bist du nicht da, startet um 18:15 automatisch die Samstags-Show).

Alle Zeiten sind **Berlin-Zeit**. Das Spiel rechnet intern in UTC und stellt Sommer-/Winterzeit selbst um
(Sommerzeit 2026: 29.03. bis 25.10.; danach Winterzeit bis 28.03.2027). Du musst nichts umstellen.

| Wort | Bedeutung |
|---|---|
| **Börsentag** | 20 Minuten = ein Tag/Nacht-Zyklus der Stadt. Beginnt immer zur vollen Stunde, :20 und :40 |
| **Glocke** | Läutet zu Beginn jedes Börsentags (bei Sonnenaufgang). Danach ist der Gewinn-Transfer wieder frei |
| **Plan-Event** | Ein Markt-Ereignis, das schon Tage vorher im Kalender des Terminals steht (Crash-Freitag, Rally-Mittwoch) |
| **Admin-Fenster** | Zeit rund um ein Markt-Event von dir. Zählt **nicht** für die Liga (HUD-Chip „ADMIN-ABUSE aktiv – zählt nicht für die Liga“) |
| **LiveConfig** | Werte, die du im Admin-Panel → **Live-Ops** ohne neue Datei änderst. Gilt sofort auf allen Servern |
| **Experience Event** | Ein Termin, den Roblox auf deiner Spielseite anzeigt (Spieler können „Benachrichtigen“ drücken) |

---

## 1. Die Rhythmen (alles automatisch)

### 1.1 Jeder Börsentag (alle 20 Minuten)

| Minute im Börsentag | Uhr (Beispiel) | Was passiert |
|---|---|---|
| :00 | 14:00 · 14:20 · 14:40 | **Glocke** bei Sonnenaufgang · Gewinn-Transfer wieder frei · Tagesbilanz · Ruf-Punkte |
| :03 · :07 · :11 · :15 | 14:03, 14:07 … | **Quartalszahlen** (je 3 Firmen) |
| :10 | 14:10 · 14:30 · 14:50 | **Makro-Termin** + **Welt-Event** (Rotation, siehe 1.2) |
| :19 | 14:19 · 14:39 · 14:59 | **Dividenden-Ex-Tag** |
| laufend | Ø alle 40 s | eine Schlagzeile im ganzen Markt (Fakt 55 % · Gerücht 25 % · „wie erwartet“ 20 %) |
| ca. alle 3,5 h | zufällig aus dem Wochen-Plan | **Crash oder Rally** mit 3 Minuten Warnstufe vorher |

### 1.2 Welt-Events um :10 (Rotation, auf allen Servern gleich)
Reihenfolge `Config.Events.Rotation = { "Truck", "Drones", "BuildBoom", "Press" }`, dann wieder von vorn:

| # | Event | Dauer | Belohnung (alles CR oder Trader-Wissen, nie Robux-Bezug) |
|---|---|---|---|
| 0 | **Geldtransporter** | 120 s | 30 Bündel je Spieler, je Bündel 20 s Dauer-Einkommen; ab 10 Bündeln +50 Saison-XP |
| 1 | **Drohnen-Lieferung** | 120 s | 8 Pakete je Spieler, je Paket 60 s Dauer-Einkommen |
| 2 | **Bau-Boom** | 300 s | Etagen- und Raum-Stufen-Kosten −25 % (Timer im HUD) |
| 3 | **Pressekonferenz** | 90 s | Roboter-CEO zeigt Analysten-Urteile 13 min vor den Quartalszahlen + Quiz (3 Fragen, 2 richtig = +50 Trader-XP) |

Pickups (Bündel, Pakete, Münzen) sieht und sammelt **jeder Spieler für sich** – niemand schnappt sie weg.

### 1.3 Jede volle Stunde

| Uhr | Event | Wirkung |
|---|---|---|
| hh:00–hh:01 | **Glocken-Moment** an der Börsenglocke | ≥ 3 Spieler in der Glocken-Zone (Studio: ≥ 1) → ganzer Server ×1,2 Einkommen für 5 min |
| hh:15 | **Sky-Show** (Nacht) | Fassaden-Lichtshow + Feuerwerks-Beams, Respekt zählt 10 min doppelt |

### 1.4 Jeden Tag

| Uhr (Berlin) | Event |
|---|---|
| 02:00 Sommer / 01:00 Winter (= 00:00 UTC) | neuer Tag: Login-Kalender, 3 Tagesquests, Akademie-Lektion, Gratis-Sofortbau-Token |
| 19:00–20:00 | **Power-Hour**: Trader-XP ×2 (für alle gleich) |

---

## 2. Der Wochenplan

| Wann (Berlin) | Event | Du musst | UTC Sommer / Winter |
|---|---|---|---|
| Mo 02:00 Sommer / 01:00 Winter | **Neue Woche**: neuer Markt-Seed, neue Liga-Woche; Liga-Belohnungen der Vorwoche beim nächsten Beitritt | nichts | Mo 00:00 / Mo 00:00 |
| Mi 19:00 | **Rally-Mittwoch**: angekündigte Sektor-Rally (Stärke 12 %, der Sektor wechselt jede Woche) | nichts | 17:00 / 18:00 |
| Fr 19:00 | **Crash-Freitag**: angekündigter Crash über alle Werte (Stärke 18 %, etwa die Hälfte kommt danach zurück) + Bär-Event auf der Plaza | nichts | 17:00 / 18:00 |
| Sa 16:00 | **Wochen-Update veröffentlichen** (neue Deko, Auto, Saison-Inhalte, Fehlerbehebungen) | **ja** (Publish, Kapitel 20 der ANLEITUNG) | 14:00 / 15:00 |
| Sa 17:00 | **IPO-Erstnotiz** (neue Firma aus der Saison-Liste, 60 s Handelspause, kaufbar ab Fondsmanager) | nichts | 15:00 / 16:00 |
| Sa 18:00 | **Admin-Abuse mit dir** (Abschnitt 3) | freiwillig | 16:00 / 17:00 |
| Sa 18:15 | **Automatische Samstags-Show**, falls du bis 18:14:50 keine Show gestartet hast | nichts | 16:15 / 17:15 |
| So 20:00 | **Bilanz-Sonntag**: Liga-Finale-Show, Top-10-Hologramme im Börsensaal | nichts | 18:00 / 19:00 |

Woher kommen die Zeiten? Markt-Termine stehen in `Config.Market.Weekly` (CrashFriday, RallyWednesday, AutoShow, Ipo),
alles andere in `Config.Events.Weekly` (PowerHour, UpdatePublish, AdminAbuse, AutoShow, LeagueFinale).
**Ändere diese Zeiten nur zusammen mit Claude** – sie stehen auch im Kalender des Terminals und auf der Spielseite.

### 2.1 Die IPO-Termine von Saison 1 (aus `Config.Market.IpoPipeline`)

| Samstag 17:00 | Firma | Kürzel | Sektor |
|---|---|---|---|
| 24.10.2026 | Neuronauten | NRNT | Tech & KI |
| 31.10.2026 | Flora Energy | FLRA | Energie & Klima |
| 07.11.2026 | Mondwerk | MNDW | Mobilität & Raumfahrt |
| 14.11.2026 | Robochef | RBCF | Konsum & Food |

24 Stunden vorher steht der **Prospekt** im Kalender (Fundamentaldaten, Sektor, Analysten-Hinweise). Ab dem 21.11.2026 gibt es nur
noch IPOs, wenn Claude neue Firmen für Saison 2 anlegt (IDs ab 104, nie eine alte Nummer wiederverwenden).

> ⚠️ **Hinweis:** Der Skyline-Pass Saison 1 läuft laut `Config.Season` vom **12.10. bis 09.11.2026**, die IPO-Reihe von Saison 1
> laut `Config.Market` aber vom **19.10. bis 15.11.2026** (eine Woche später). Das stört nicht beim Spielen. Wenn du beides
> gleich haben willst, sag Claude: „Saison-Start und IPO-Woche angleichen“.

---

## 3. Samstag: dein Ablauf als Besitzer

### 3.1 Checkliste

| Uhrzeit | Schritt |
|---|---|
| bis Sa 16:00 | Update fertig? Dann **Publish** (ANLEITUNG Kapitel 20). Kein Update? Einfach nichts tun |
| Fr oder Sa Mittag | Auf deinen Kanälen „AKYTEX Games“ ankündigen: „Heute 18:00 Admin-Abuse!“ (Vorlage: KOPIERVORLAGEN Abschnitt 9) |
| 17:55 | Spiel öffnen (als **RizzG315**), Taste **P** → Admin-Panel. Reiter **Dashboard**: Bus-Status grün? |
| 18:00–18:14 | Show starten (siehe 3.2). **Sobald du ein Markt-Event oder die 1-Klick-Show startest, wird die Automatik-Show abgesagt.** |
| 18:00–19:00 | Show durchziehen, Ansagen machen, Boss-Auftritt, Geldregen |
| danach | Admin-Panel → **Markt → Normalisieren** (beendet alle Markt-Effekte über 60 s), wenn noch etwas läuft |

### 3.2 Was du starten kannst (Admin-Panel → Reiter **Events** bzw. **Markt**)

| Event | Grenzen (das Spiel lässt nichts darüber zu) | Hinweis |
|---|---|---|
| **Samstags-Show (1 Klick)** | Banner → Golden Hour ×2 für 30 min → Rally +15 % im Sektor der Woche (nach 30 s) → Geldregen nach 75 s für 180 s → Feuerwerk nach 260 s | einfachster Weg; sagt die Automatik ab |
| Mega-Rally / Mega-Crash | +5 … +50 % bzw. −5 … −50 %, Rampe 30–300 s, Abklingen 5–60 min, Crash optional mit 3-min-Warnung | immer **alle Server**, Admin-Fenster |
| Firma pushen / abstürzen | ±5 … 50 % auf einen Wert | Firmen-Laden in der Stadt leuchtet |
| Admin-Eilmeldung | Text DE/EN ≤ 80 Zeichen (gefiltert), Ziel Wert/Sektor, Stärke 1–4, Richtung | erscheint auf allen Servern mit normalem 8-s-Lesefenster |
| Handelspause / Weiter | 10 s – 10 min | Ticker-Wände zeigen „HANDELSPAUSE“ |
| IPO starten | Firma aus der Liste | Erstnotiz 10 min nach dem Start |
| Volatilität | ×0,5 … ×3 für 5–30 min | Wetter wird stürmisch/ruhig |
| Normalisieren | – | beendet alle Admin-Markt-Effekte über 60 s |
| Geldregen | 60–300 s, lokal oder global | je Spieler max. 30 Münzen, je Münze 2 min Dauer-Einkommen |
| Golden Hour | ×2 oder ×3, 5–60 min | Event-Multiplikator nie über ×3, gesamt nie über ×10 |
| XP-Rausch | Trader-XP ×2, 15–60 min | Liga bleibt unberührt |
| Bau-Boom | 10 min | Etagenkosten −50 %, Bauzeit −90 % |
| Lightshow / Feuerwerk / Konfetti / Glocken-Show | – | nur Show |
| Boss-Auftritt | 60–300 s | dein Avatar 8× auf dem Börsensaal-Dach, winkend |
| Alle in den Börsensaal | nur dieser Server | Kamera-Schwenk + Teleport |

**Harte Regeln (macht das Spiel automatisch):** nichts wird gelöscht, kein Event trifft einzelne Spieler negativ, keine Käufe werden
berührt, jedes Markt-Event wird angekündigt und öffnet ein Admin-Fenster (zählt nicht für die Liga). **Deine eigenen Trades sind
120 s vor und nach deinen Markt-Events gesperrt** und du zählst nie für die Liga.

### 3.3 Wenn du nicht da bist
Um **18:15** läuft die **automatische Samstags-Show** genau wie die 1-Klick-Show. Du musst nichts vorbereiten.

---

## 4. Saison-Plan (je Saison 4 Wochen, Skyline-Pass mit 50 Stufen)

Je Saison: 2–4 IPO-Firmen, ein Deko-Set, 1 Auto, 1 Fassade, Pass mit 50 Stufen, ein Wochen-Thema (DESIGN.md §E2).

| Saison | Thema (Spec) | Termine bei 4-Wochen-Takt ab 12.10.2026 (Mitternacht UTC) |
|---|---|---|
| S1 | **„Neon-Skyline“** (Launch) – Deko-Set S1 (8 Teile), Uhr Skyline-Chrono, Auto Orbit-R, Fassade Holo-Prisma | 12.10.2026 – 09.11.2026 (steht so in `Config.Season`) |
| S2 | „Raumfahrt-Rallye“ (Mondwerk-Schwerpunkt, Raumfahrt-Deko) | 09.11.2026 – 07.12.2026 |
| S3 | „Energie-Wende“ | 07.12.2026 – 04.01.2027 |
| S4 | „Gaming-Boom“ | 04.01.2027 – 01.02.2027 |
| S5 | „Winter-Börse“ (Schnee-Partikel, Glas-Weihnachtsbaum auf der Plaza) | 01.02.2027 – 01.03.2027 |
| S6 | „Neujahrs-Glocke“ | 01.03.2027 – 29.03.2027 |

> 💡 **Tipp:** „Winter-Börse“ ist für Dezember gedacht. Im 4-Wochen-Takt fällt der Dezember auf **S3** und Neujahr auf **S4**.
> Tausch die Themen einfach (S3 Winter-Börse, S4 Neujahrs-Glocke, danach Energie-Wende und Gaming-Boom). Die Reihenfolge ist frei.

**Was passiert, wenn du keine neue Saison einträgst?** Nichts Schlimmes: `Config.Season.Rolling` (an, 28 Tage) startet automatisch
„Saison 2, 3, …“ mit den Belohnungen der letzten Saison und ehrlichem Enddatum. Der Pass ist nie leer.
**Neue Saison eintragen:** ANLEITUNG Kapitel 16. Neue Firmen, Autos, Fassaden und Deko-Sets brauchen Code → Claude fragen.

**Saison-Start-Routine (Montag der neuen Saison):**
1. Am Samstag davor das Update mit der neuen Saison veröffentlichen (16:00).
2. Spielseiten-Titel auf `[S2] AKYTEX TYCOON 🏙️📈 Börse & Tower` ändern (KOPIERVORLAGEN Abschnitt 1).
3. Experience Event „Saison-Start“ anlegen (KOPIERVORLAGEN Abschnitt 8).
4. Neuen Code für die Saison anlegen (ANLEITUNG Kapitel 17) und auf deinen Kanälen posten.
5. Thumbnail mit dem Saison-Thema tauschen (Ideen: KOPIERVORLAGEN Abschnitt 4).

---

## 5. Experience Events auf der Spielseite

Lege diese wiederkehrenden Termine im Creator Dashboard an (Anleitung: ANLEITUNG Kapitel 15, Texte: KOPIERVORLAGEN Abschnitt 8).
Lege sie jeweils für die **nächsten 4 Wochen** an und ergänze sie einmal im Monat.

| Event | Wann | Dauer |
|---|---|---|
| Rally-Mittwoch | Mi 19:00 | 30 min |
| Crash-Freitag | Fr 19:00 | 30 min |
| IPO-Erstnotiz | Sa 17:00 | 30 min |
| Admin-Abuse-Samstag | Sa 18:00 | 60 min |
| Bilanz-Sonntag | So 20:00 | 30 min |
| Saison-Start | Montag des Saison-Starts, 18:00 | 2 h |

Power-Hour (täglich 19:00) und die stündlichen Events brauchst du **nicht** als Experience Event anzulegen – sonst wird die Liste zu voll.

---

## 6. Event-Rotation ändern

### 6.1 Live (ohne neue Datei, sofort auf allen Servern)
**Admin-Panel → Reiter Live-Ops → `Events.Rotation`** → Liste aus `Truck`, `Drones`, `BuildBoom`, `Press` wählen (1 bis 4 Einträge,
keine doppelten) → **Speichern**. Beispiel: nur `Truck, Drones` = abwechselnd Geldtransporter und Drohnen.

### 6.2 Dauerhaft in der Datei
Explorer: **ReplicatedStorage → Shared → Config → Events** doppelklicken → **Cmd + F** → `Events.Rotation` →
z. B. `Events.Rotation = { "Truck", "BuildBoom", "Drones", "Press" }` → **Play** testen → **Publish**.

### 6.3 Alle Live-Werte (Admin-Panel → Live-Ops; das Spiel klemmt jeden Wert auf diese Grenzen)

| Live-Wert | Bedeutung | Erlaubt |
|---|---|---|
| `Market.NewsMeanGap` | wie oft Schlagzeilen kommen (größer = seltener) | 300 – 6000 |
| `Events.Rotation` | Reihenfolge der Welt-Events | 1–4 aus Truck/Drones/BuildBoom/Press |
| `Events.BoostPause` | **Notschalter:** alle persönlichen Boosts pausieren | an/aus |
| `Events.BellMoment.Mult` | Stärke Glocken-Moment | 1 – 1,5 |
| `Events.BuildBoom.Pct` | Rabatt beim Bau-Boom (0,25 = −25 %) | 0,05 – 0,5 |
| `Events.Truck.Bundles` | Bündel je Spieler beim Geldtransporter | 5 – 60 |
| `Events.RainCoinsMax` | Münzen je Spieler beim Geldregen | 5 – 30 |
| `Tower.Mult.Bull` / `Tower.Mult.Parade` | Bullen-Bonus / Bullen-Parade | je 1 – 2 |
| `Tower.Mult.BellMoment` | Glocken-Moment im Turm-Einkommen | 1 – 1,5 |
| `Tower.Mult.EventMax` | höchster Event-Multiplikator | 1 – 3 |
| `Shop.Disabled.<Key>` | **Notschalter:** einen Pass oder ein Produkt im Shop sperren (z. B. `Shop.Disabled.BullParade`) | an/aus |
| `Rewards.Codes.<CODE>` | Code anlegen/ändern (nur CR oder Kosmetik) | höchstens 1.000.000 CR |

---

## 7. Notschalter (wenn etwas schiefgeht)

| Problem | Sofort-Maßnahme | Danach |
|---|---|---|
| Ein Produkt oder Pass macht Probleme | Admin-Panel → **Live-Ops** → `Shop.Disabled.<Key>` = an. Der Shop zeigt es nicht mehr an. **Schon bezahlte Käufe werden trotzdem immer gutgeschrieben** | Fehler an Claude schicken |
| Boosts sind zu stark / Fehler im Einkommen | **Live-Ops** → `Events.BoostPause` = an | Claude fragen |
| Markt spielt verrückt (Admin-Event zu stark) | **Markt → Normalisieren** (60 s) oder **Handelspause** (10 s – 10 min) | – |
| Wartung nötig | **Live-Ops** → Wartungs-Banner einschalten (Text für alle Spieler) | Update veröffentlichen |
| Fehler im neuen Update | alte, funktionierende `AkytexTycoon.rbxlx` wieder mit **Publish to Roblox As… → Overwrite** darüberspielen (ANLEITUNG Kapitel 8.2) | Claude fragen |
| Automatik-Show soll ausfallen | vor 18:14:50 selbst ein Markt-Event oder die 1-Klick-Show starten (sendet `CancelAutoShow`) | – |
| Ein Code wird missbraucht | **Live-Ops** → Code entfernen bzw. Ablaufdatum in die Vergangenheit setzen | – |

Live-Werte sind **validiert und geklemmt** – du kannst nichts kaputt machen, was über die Grenzen geht.
Jede Admin-Aktion steht im Reiter **Moderation** (letzte 500).

---

## 8. Wöchentliche Routine (15 Minuten)

| Tag | Aufgabe |
|---|---|
| Montag | Creator Dashboard → **Analytics**: Besucher, Spielzeit, D1/D7, Käufe der Vorwoche anschauen (Ziele: ANLEITUNG Kapitel 21). Admin-Panel → **Statistik**: CR-/AKY-Menge, meistgehandelte Werte, verdächtige Spieler |
| Mittwoch | Kurz-Post „Heute 19:00 Rally-Mittwoch“ |
| Donnerstag | Wünsche für das Wochen-Update an Claude schicken (neue Deko, Auto, Fehler) |
| Freitag | Kurz-Post „Heute 19:00 Crash-Freitag – beruhige den Bären!“ |
| Samstag | 16:00 Update veröffentlichen · 18:00 Admin-Abuse (Abschnitt 3) |
| Sonntag | 20:00 Bilanz-Sonntag ansehen, Clip für TikTok/Shorts aufnehmen (Fotomodus **F7**, als Admin auch **Kräfte → Show-Kamera**) |
| einmal im Monat | Experience Events für die nächsten 4 Wochen anlegen · Codes erneuern · Fragebogen prüfen, falls sich Inhalte geändert haben |

---

## 9. Was du nie tun solltest
- Keine Belohnungen für Likes, Favoriten oder Einladungen außerhalb der eingebauten Funktionen (Roblox-Regel).
- Keine „Nur heute!“- oder „Letzte Chance!“-Posts für Robux-Artikel, keine falschen Countdowns (Kinder-Schutz, UWG).
- Keine Markt-Events mit echten Firmennamen oder echten Nachrichten in der Admin-Eilmeldung.
- Kein Hinweis auf die AKYTEX-Website, App oder echtes Trading in Ansagen, Event-Texten oder auf der Spielseite.
- Kein Event, das Spielern etwas wegnimmt (das Spiel verhindert es ohnehin).
