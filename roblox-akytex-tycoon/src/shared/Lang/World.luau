-- =====================================================================
--  AKYTEX TYCOON – Texte "world." (Shared/Lang/World)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Nur Schlüssel mit Präfix "world.". Vertrag: DESIGN.md §C15, §A4, §A5.
--  Prompt-Texte in der Stadt: der Server setzt Englisch als Startwert (Attribut "TextKey"/"ObjectKey"), WorldLook
--  übersetzt jeden Prompt clientseitig in die Spielersprache. Markennamen auf Schildern stehen in Config.City.Signs.
--  Kurz, ruhig, keine Wett-/Glücksspiel-Wörter (Wortliste §0.7).
-- =====================================================================

return {
	de = {
		-- Prompt-Aktionen
		["world.prompt.terminal"] = "Terminal öffnen",
		["world.prompt.garage"] = "Autohaus öffnen",
		["world.prompt.tuning"] = "Tuning-Box",
		["world.prompt.boutique"] = "Boutique öffnen",
		["world.prompt.boards"] = "Bestenlisten",
		["world.prompt.academy"] = "Lektion starten",
		["world.prompt.tour"] = "Tower besuchen",
		["world.prompt.helipadUp"] = "Hoch zum Helipad",
		["world.prompt.helipadFly"] = "Schnellreise zur Plaza",
		["world.prompt.clubUp"] = "Zur Dachterrasse",
		["world.prompt.clubDown"] = "Zurück in den Börsensaal",

		-- Prompt-Objekte
		["world.object.terminal"] = "ΛKYTEX Terminal",
		["world.object.motors"] = "Λ Motors",
		["world.object.tuning"] = "Lackier-Box",
		["world.object.chrono"] = "Chronohaus",
		["world.object.boards"] = "Hologramm",
		["world.object.academy"] = "Lern-Kapsel",
		["world.object.tour"] = "Tower-Tour",
		["world.object.helipad"] = "Helipad",
		["world.object.club"] = "Club-Lift",

		-- Meldungen
		["world.clubOnly"] = "Die Dachterrasse gehört dem Vorstands-Club",
		["world.travelPlaza"] = "Willkommen zurück auf der Plaza",
		["world.travelHelipad"] = "Aussicht genießen – Schnellreise zur Plaza steht bereit",
		["world.travelRoof"] = "Willkommen auf der Dachterrasse",
		["world.travelBusy"] = "Kurz warten …",

		-- Markt-Wetter (Anzeige, z. B. Fotomodus/Debug)
		["world.weather.clear"] = "Klar",
		["world.weather.clouds"] = "Wolkig",
		["world.weather.storm"] = "Sturm",
	},
	en = {
		-- Prompt actions
		["world.prompt.terminal"] = "Open terminal",
		["world.prompt.garage"] = "Open dealership",
		["world.prompt.tuning"] = "Tuning booth",
		["world.prompt.boutique"] = "Open boutique",
		["world.prompt.boards"] = "Leaderboards",
		["world.prompt.academy"] = "Start lesson",
		["world.prompt.tour"] = "Visit a tower",
		["world.prompt.helipadUp"] = "Up to the helipad",
		["world.prompt.helipadFly"] = "Fast travel to the plaza",
		["world.prompt.clubUp"] = "To the roof terrace",
		["world.prompt.clubDown"] = "Back to the exchange hall",

		-- Prompt objects
		["world.object.terminal"] = "ΛKYTEX Terminal",
		["world.object.motors"] = "Λ Motors",
		["world.object.tuning"] = "Paint booth",
		["world.object.chrono"] = "Chronohaus",
		["world.object.boards"] = "Hologram",
		["world.object.academy"] = "Learning capsule",
		["world.object.tour"] = "Tower tour",
		["world.object.helipad"] = "Helipad",
		["world.object.club"] = "Club lift",

		-- Messages
		["world.clubOnly"] = "The roof terrace belongs to the Executive Club",
		["world.travelPlaza"] = "Welcome back to the plaza",
		["world.travelHelipad"] = "Enjoy the view – fast travel to the plaza is ready",
		["world.travelRoof"] = "Welcome to the roof terrace",
		["world.travelBusy"] = "One moment …",

		-- Market weather (display, e.g. photo mode/debug)
		["world.weather.clear"] = "Clear",
		["world.weather.clouds"] = "Cloudy",
		["world.weather.storm"] = "Storm",
	},
}
