# Roblox-Skripte: der typische Roblox-Look

Drei Skripte für Roblox Studio, die dein Spiel nach typischem Roblox aussehen lassen:

| Script | Art | Kommt nach | Was es macht |
|---|---|---|---|
| `KlassischerLook` | Script | **ServerScriptService** | Noppen (Studs) auf allen Blöcken, grüne Baseplate, klassisches Licht, Standard-Himmel, klotzige Avatare |
| `MuenzenUndShop` | Script | **ServerScriptService** | Münzen in der Rangliste, Münzen zum Einsammeln, Shop mit Turbo-Schuhen, Sprungfedern und Glitzer |
| `RobloxUI` | LocalScript | **StarterPlayer › StarterPlayerScripts** | Die bunte Spiel-Oberfläche: Münzanzeige, Knöpfe links, Fenster für Shop, Inventar und Optionen |

## Einbauen (5 Minuten)

1. Roblox Studio öffnen → **Neu** → Vorlage **Baseplate**.
2. Im **Explorer** mit der Maus über **ServerScriptService** → auf **+** → **Script**.
   Umbenennen in `KlassischerLook`, alles darin löschen und den Inhalt von
   [`ServerScriptService/KlassischerLook.server.lua`](ServerScriptService/KlassischerLook.server.lua) einfügen.
3. Genauso ein zweites **Script** in **ServerScriptService**: `MuenzenUndShop` mit dem Inhalt von
   [`ServerScriptService/MuenzenUndShop.server.lua`](ServerScriptService/MuenzenUndShop.server.lua).
4. **StarterPlayer** aufklappen → über **StarterPlayerScripts** → **+** → **LocalScript**.
   Name `RobloxUI`, Inhalt von [`StarterPlayerScripts/RobloxUI.client.lua`](StarterPlayerScripts/RobloxUI.client.lua).
5. Auf **Play** (F5) drücken. Fertig!

Die Noppen und das neue Licht siehst du erst, wenn das Spiel läuft – die Skripte ändern deinen Place nicht dauerhaft.

## Noch klassischer: zwei Klicks in Studio

Diese zwei Sachen darf ein Script nicht ändern, die musst du selbst einstellen:

- **Licht-Technik:** Im Explorer **Lighting** anklicken → bei den Eigenschaften **Technology** auf **Voxel** stellen.
- **R6-Avatare** (die alten mit 6 Körperteilen): **Spieleinstellungen** (Game Settings) → **Avatar** → Avatar-Typ **R6**.
  Je nach Studio-Version findest du das auch im Reiter **Avatar** unter **Avatar Settings**.
  Ist die Einstellung ausgegraut, das Spiel erst einmal veröffentlichen (**Datei → Auf Roblox veröffentlichen**).

## Anpassen

**KlassischerLook** – ganz oben im Script steht `EINSTELLUNGEN`. Mit `true`/`false` schaltest du alles an und aus:

```lua
Noppen = true,
BaseplateFarbe = BrickColor.new("Bright green"),  -- z. B. "Dark green" oder "Medium stone grey"
KlotzigeAvatare = true,
StandardGesicht = false,  -- true = alle bekommen das klassische Lächeln
```

Ein Teil soll keine Noppen bekommen? Teil auswählen → Eigenschaften → ganz unten **Attribute** → **+** →
Name `KeineNoppen`, Typ **Boolean**, Haken an.

**Münzen** – Jedes Teil mit dem Tag `Muenze` ist eine Münze (Teil auswählen → Eigenschaften → **Tags** → **+** → `Muenze`).
Mit dem Attribut `Wert` (Number) bestimmst du, wie viele Münzen sie gibt. Solange du keine eigenen Münzen hast,
legt das Script 12 Beispiel-Münzen im Kreis um den Spawn.

**Shop** – In `MuenzenUndShop` steht die Liste `SHOP`. Neuer Artikel = einen Block kopieren und ändern:

```lua
{
	Id = "Riesig",            -- nur Buchstaben, keine Leerzeichen oder Umlaute
	Titel = "Riesen-Trank",
	Text = "Du wirst groß",
	Icon = "🧪",
	Preis = 100,
	Farbe = Color3.fromRGB(255, 120, 0),
	Wirkung = function(figur, humanoid)
		-- was beim Kauf (und nach jedem Respawn) passiert
	end,
},
```

Der Shop in der Oberfläche zeigt neue Artikel automatisch an.

**Oberfläche** – Ganz oben in `RobloxUI` stehen `SCHRIFT` und `FARBE`. Andere typische Roblox-Schriften:
`Enum.Font.LuckiestGuy`, `Enum.Font.GothamBold`, `Enum.Font.BuilderSansBold`.

## Gut zu wissen

- Münzen und gekaufte Sachen werden **nicht gespeichert** – wer das Spiel verlässt, fängt wieder bei 0 an.
  Speichern geht mit dem **DataStoreService**; dafür in den Spieleinstellungen unter **Sicherheit**
  „Studio-Zugriff auf API-Dienste“ einschalten.
- Gekauft wird auf dem Server: Ein Spieler kann sich keine Münzen oder Artikel „herbeischummeln“.
- Die Dateiendungen `.server.lua` und `.client.lua` passen zu **Rojo**, falls du später mit VS Code arbeiten willst.
