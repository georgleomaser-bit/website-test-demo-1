# Admin-Panel – Wünsche des Besitzers (verbindlich, ergänzt DESIGN.md)

Nur der Besitzer des Spiels (game.CreatorId, Studio-Test zählt) hat das Panel. Jede Aktion wird vom
SERVER geprüft. Niemand kann Admin kaufen. Admin-Waffen und Admin-Kräfte gibt es für niemand anderen.

## Admin-Kräfte (für sich selbst, an/aus)
- **Aimbot**: Zielhilfe auf den Kopf des nächsten Gegners (sichtbar/sanft oder "Silent Aim" – der Server
  akzeptiert Admin-Schüsse auf das anvisierte Ziel), dazu optional Triggerbot (schießt automatisch).
- **ESP / Wallhack**: alle Spieler durch Wände sehen (Highlight + Name + Leben).
- **Fly** (Taste G), **Noclip**, **Speed**, **Super-Sprung**, **God Mode**, **Unsichtbar**.
- **Unendlich Munition**, **kein Nachladen**, **Rapid Fire**, **One-Shot-Kill**.

## Waffen
- Jede Waffe / jeden Skin sich selbst oder anderen geben.
- **Admin-Waffen** (nur Besitzer, extrem stark, nicht kaufbar): z. B. Orbital-Laser, Raketen-Minigun,
  Schwarzes-Loch-Kanone, Blitz-Gewehr – aus Parts gebaut, mit krassen Effekten.

## Spieler
- Kick, Ban (mit Grund/Dauer), Unban, Ban-Liste, Einfrieren, Herholen (Bring), Hingehen (Goto),
  Töten, Heilen, Zuschauen.
- Währung, Kisten/Keys, Skins, XP an Spieler geben.

## Server & Events
- Match starten/beenden, Modus/Map festlegen, Bots spawnen (Schwierigkeit), Server sperren.
- **Ansagen** an alle wie in Steal a Brainrot: mit Avatar des Besitzers + blauem Haken, ohne Kasten,
  auch serverübergreifend (MessagingService).
- **Admin-Abuse-Event**: globale Ansage + Server-Boost (z. B. 2x Coins / 2x XP für alle für X Minuten),
  serverübergreifend.

## Fairness-Schutz (damit das Spiel fair bleibt)
- Matches, in denen der Besitzer Admin-Kräfte (Aimbot, God Mode, One-Shot, Admin-Waffen …) benutzt,
  zählen NICHT für Ranked/ELO, globale Bestenlisten und Statistiken der anderen Spieler.
  Die Gegner verlieren in so einem Match nichts (kein ELO-Verlust, keine Niederlage in der Statistik).
