-- =====================================================================
--  AKYTEX TYCOON – Texte "tui." (Shared/Lang/TowerUi)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Nur Schlüssel mit Präfix "tui.". Vertrag: DESIGN.md §C15,
--  §D WP8 (Tower-Menü, Aufzug, Willkommen-zurück-Bericht, Zukunfts-Ich, Effekte), §B1, §B4, §B8.2, §B4.10.
--  Platzhalter wie string.format: %s = Text (auch fertig formatierte CR/AKY/Dauer), %d = ganze Zahl, %% = Prozent.
--  Namen von Stufen/Abteilungen/Personal/Fassaden stehen in Config.Tower ({ de, en }), nicht hier.
--  Sätze kurz und ruhig, keine Wett-/Glücksspiel-Wörter (Wortliste §0.7, Vertrags-Prüfer BANNED_WORDS).
--  Dynamische Schlüssel: tui.tab.<overview|floors|staff|facade|visit>, tui.skinHint.<Skin-Schlüssel ohne Pass>.
-- =====================================================================

return {
	de = {
		-- Fenster & Tabs
		["tui.title"] = "Dein Tower",
		["tui.tab.overview"] = "Übersicht",
		["tui.tab.floors"] = "Etagen",
		["tui.tab.staff"] = "Personal",
		["tui.tab.facade"] = "Fassade",
		["tui.tab.visit"] = "Besuchen",
		["tui.loading"] = "Lädt …",
		["tui.notReady"] = "Noch nicht verfügbar – bald!",
		["tui.more"] = "Mehr",
		["tui.on"] = "An",
		["tui.off"] = "Aus",
		["tui.owned"] = "Im Besitz",
		["tui.active"] = "Aktiv",
		["tui.view"] = "Ansehen",
		["tui.perSec"] = "%s/s",
		["tui.fromStage"] = "ab Stufe %s",
		["tui.topOnly"] = "nur oberste Etage",
		["tui.licenceLevel"] = "Lizenz %s",
		["tui.floorsShort"] = "%s Etagen",
		["tui.floorLabel"] = "Etage %s",
		["tui.plotFree"] = "Freier Bauplatz",

		-- Übersicht: Kennzahlen
		["tui.stat.stage"] = "Stufe",
		["tui.stat.floors"] = "Etagen",
		["tui.stat.income"] = "Ertrag",
		["tui.stat.mult"] = "Multiplikator",

		-- Bauen
		["tui.build.title"] = "Bauen",
		["tui.build"] = "Etage bauen",
		["tui.build.running"] = "Etage %s im Bau – fertig in %s",
		["tui.build.helpers"] = "%s Helfer bauen mit",
		["tui.build.instant"] = "Sofort fertig (%d)",
		["tui.build.express"] = "Express (%d)",
		["tui.build.locked"] = "Gesperrt",
		["tui.build.next"] = "Etage %s · %s",
		["tui.build.gain"] = "+%s/s Ertrag · Bauzeit %s",
		["tui.build.stageUp"] = "Danach: neue Stufe „%s“",

		-- Tresor & Gewinn-Transfer
		["tui.vault.title"] = "Tresor",
		["tui.vault.collect"] = "Einsammeln",
		["tui.vault.hint"] = "Voll heißt: es kommt nichts mehr dazu.",
		["tui.transfer.title"] = "Gewinn-Transfer",
		["tui.transfer.hint"] = "Bau-Kurs deiner Lizenz: 1 AKY = %s",

		-- Effizienz
		["tui.eff.title"] = "Effizienz %s/%s",
		["tui.eff.next"] = "Nächste Stufe: %s",
		["tui.eff.buy"] = "Verbessern",
		["tui.eff.max"] = "Maximale Effizienz erreicht",

		-- Mehr
		["tui.autoPlan"] = "Auto-Plan",
		["tui.autoPlanTitle"] = "Vorschlag für deine Abteilungen",
		["tui.autoPlanRow"] = "Etage %d: %s → %s",
		["tui.boutique"] = "Deko kaufen",
		["tui.future.button"] = "Zukunfts-Ich",
		["tui.ipoPreview"] = "Börsengang-Vorschau",

		-- Etagen
		["tui.noFloors"] = "Noch keine Etage – bau deine erste!",
		["tui.floors.all"] = "Alle Etagen",
		["tui.floor.title"] = "Etage %d · %s · Stufe %d",
		["tui.floor.income"] = "Ertrag %s/s",
		["tui.floor.levelUp"] = "Auf Stufe %d · %s",
		["tui.floor.private"] = "Privat machen",
		["tui.floor.public"] = "Öffentlich machen",
		["tui.floor.goto"] = "Hinfahren",
		["tui.floor.rooms"] = "Abteilung wechseln (%s)",
		["tui.floor.staff"] = "Personal %d/%d",
		["tui.floor.decor"] = "Deko-Plätze (%d)",
		["tui.staffBoost"] = "Personal",
		["tui.staffPlus"] = "Mehr Personal-Plätze mit dem Pass",
		["tui.fire"] = "Entlassen",
		["tui.fireConfirm"] = "Sicher? Nochmal tippen",
		["tui.hireFor"] = "Einstellen · %s",
		["tui.hireFree"] = "Einstellen · gratis",

		-- Deko-Plätze
		["tui.decor.empty"] = "Leerer Platz",
		["tui.decor.place"] = "Tippen zum Platzieren",
		["tui.decor.remove"] = "Tippen zum Entfernen",
		["tui.decor.pick"] = "Platz %s: Deko wählen",
		["tui.decor.none"] = "Dein Lager ist leer.",
		["tui.decor.count"] = "Lager %s · Komfort %s",

		-- Personal (Lobby)
		["tui.lobby.title"] = "Lobby-Personal",
		["tui.staff.summary"] = "Dein Team",
		["tui.staff.hint"] = "Personal wirkt auf die Etage, auf der es arbeitet.",

		-- Fassade
		["tui.facade.skins"] = "Fassaden",
		["tui.facade.pass"] = "Fassaden-Pass",
		["tui.facade.neon"] = "Neon-Farbe",
		["tui.facade.crown"] = "Krone",
		["tui.facade.noCrown"] = "Keine Krone",
		["tui.facade.name"] = "Tower-Name",
		["tui.facade.adj"] = "Wort 1",
		["tui.facade.noun"] = "Wort 2",
		["tui.facade.apply"] = "Übernehmen",
		["tui.facade.layout"] = "Grundriss",
		["tui.facade.layoutHint"] = "Grundriss nach dem Börsengang behalten",
		["tui.facade.private"] = "Private Etagen: %s/%s",
		["tui.skinHint.Obsidian"] = "Login-Kalender Tag 14",
		["tui.skinHint.MarbleWhite"] = "Erfolg freischalten",
		["tui.skinHint.NeonCyber"] = "Erfolg freischalten",
		["tui.skinHint.HoloPrism"] = "Skyline-Pass Premium",
		["tui.skinHint.Polar"] = "Login-Kalender Tag 28",

		-- Besuchen
		["tui.visit.title"] = "Tower besuchen",
		["tui.visit.none"] = "Gerade ist kein anderer Tower bewohnt.",
		["tui.visit.you"] = " (du)",
		["tui.visit.go"] = "Besuchen",
		["tui.visit.home"] = "Nach Hause",

		-- Aufzug & Prompts
		["tui.elevator.title"] = "Aufzug",
		["tui.elevator.lobby"] = "EG",
		["tui.elevator.private"] = "Diese Etage ist privat.",
		["tui.elevator.notInside"] = "Der Aufzug fährt nur im Tower.",
		["tui.elevator.prompt"] = "Aufzug",
		["tui.respekt.prompt"] = "Respekt geben",
		["tui.help.prompt"] = "Beim Bau helfen",
		["tui.crane"] = "Etage %s im Bau · %s",

		-- Effekte
		["tui.fx.perSec"] = "+%s/s",
		["tui.fx.stage"] = "Stufe %s: %s",
		["tui.fx.credits"] = "+%s",

		-- Willkommen zurück
		["tui.welcome.title"] = "Willkommen zurück",
		["tui.welcome.away"] = "Du warst %s weg. Das ist passiert:",
		["tui.welcome.before"] = "Vorher",
		["tui.welcome.after"] = "Jetzt",
		["tui.welcome.offline"] = "Tower offline +%s (%d %% für %s)",
		["tui.welcome.dividends"] = "Dividenden +%s",
		["tui.welcome.fills"] = "%d Orders ausgeführt",
		["tui.welcome.alerts"] = "%d Alarme ausgelöst",
		["tui.welcome.bot"] = "Bot „%s“: %s",
		["tui.welcome.built"] = "%s Etage(n) fertig gebaut",
		["tui.welcome.transfer"] = "Auto-Transfer +%s",
		["tui.welcome.quiet"] = "Alles ruhig – dein Tower hat gewartet.",
		["tui.welcome.collect"] = "Einsammeln",
		["tui.welcome.credited"] = "Schon gutgeschrieben – das hier ist nur die Übersicht.",

		-- Zukunfts-Ich
		["tui.future.title"] = "Dein Zukunfts-Ich",
		["tui.future.income"] = "In %d h verdient dein Tower ≈ %s",
		["tui.future.orders"] = "%d Schutz-Orders passen auf dein Depot auf",
		["tui.future.noOrders"] = "Tipp: Stop-Orders schützen dein Depot, während du weg bist",
		["tui.future.build"] = "Etage %s fertig in %s",
	},
	en = {
		-- Window & tabs
		["tui.title"] = "Your Tower",
		["tui.tab.overview"] = "Overview",
		["tui.tab.floors"] = "Floors",
		["tui.tab.staff"] = "Staff",
		["tui.tab.facade"] = "Facade",
		["tui.tab.visit"] = "Visit",
		["tui.loading"] = "Loading …",
		["tui.notReady"] = "Not available yet – soon!",
		["tui.more"] = "More",
		["tui.on"] = "On",
		["tui.off"] = "Off",
		["tui.owned"] = "Owned",
		["tui.active"] = "Active",
		["tui.view"] = "View",
		["tui.perSec"] = "%s/s",
		["tui.fromStage"] = "from stage %s",
		["tui.topOnly"] = "top floor only",
		["tui.licenceLevel"] = "Licence %s",
		["tui.floorsShort"] = "%s floors",
		["tui.floorLabel"] = "Floor %s",
		["tui.plotFree"] = "Free plot",

		-- Overview: stats
		["tui.stat.stage"] = "Stage",
		["tui.stat.floors"] = "Floors",
		["tui.stat.income"] = "Income",
		["tui.stat.mult"] = "Multiplier",

		-- Building
		["tui.build.title"] = "Build",
		["tui.build"] = "Build floor",
		["tui.build.running"] = "Floor %s under construction – ready in %s",
		["tui.build.helpers"] = "%s helpers are building",
		["tui.build.instant"] = "Finish now (%d)",
		["tui.build.express"] = "Express (%d)",
		["tui.build.locked"] = "Locked",
		["tui.build.next"] = "Floor %s · %s",
		["tui.build.gain"] = "+%s/s income · build time %s",
		["tui.build.stageUp"] = "Next: new stage “%s”",

		-- Vault & profit transfer
		["tui.vault.title"] = "Vault",
		["tui.vault.collect"] = "Collect",
		["tui.vault.hint"] = "Full means nothing more is added.",
		["tui.transfer.title"] = "Profit transfer",
		["tui.transfer.hint"] = "Build rate of your licence: 1 AKY = %s",

		-- Efficiency
		["tui.eff.title"] = "Efficiency %s/%s",
		["tui.eff.next"] = "Next level: %s",
		["tui.eff.buy"] = "Upgrade",
		["tui.eff.max"] = "Maximum efficiency reached",

		-- More
		["tui.autoPlan"] = "Auto plan",
		["tui.autoPlanTitle"] = "Suggestion for your departments",
		["tui.autoPlanRow"] = "Floor %d: %s → %s",
		["tui.boutique"] = "Buy decor",
		["tui.future.button"] = "Future self",
		["tui.ipoPreview"] = "IPO preview",

		-- Floors
		["tui.noFloors"] = "No floor yet – build your first!",
		["tui.floors.all"] = "All floors",
		["tui.floor.title"] = "Floor %d · %s · level %d",
		["tui.floor.income"] = "Income %s/s",
		["tui.floor.levelUp"] = "To level %d · %s",
		["tui.floor.private"] = "Make private",
		["tui.floor.public"] = "Make public",
		["tui.floor.goto"] = "Ride there",
		["tui.floor.rooms"] = "Change department (%s)",
		["tui.floor.staff"] = "Staff %d/%d",
		["tui.floor.decor"] = "Decor spots (%d)",
		["tui.staffBoost"] = "Staff",
		["tui.staffPlus"] = "More staff spots with the pass",
		["tui.fire"] = "Dismiss",
		["tui.fireConfirm"] = "Sure? Tap again",
		["tui.hireFor"] = "Hire · %s",
		["tui.hireFree"] = "Hire · free",

		-- Decor spots
		["tui.decor.empty"] = "Empty spot",
		["tui.decor.place"] = "Tap to place",
		["tui.decor.remove"] = "Tap to remove",
		["tui.decor.pick"] = "Spot %s: choose decor",
		["tui.decor.none"] = "Your storage is empty.",
		["tui.decor.count"] = "Stored %s · comfort %s",

		-- Staff (lobby)
		["tui.lobby.title"] = "Lobby staff",
		["tui.staff.summary"] = "Your team",
		["tui.staff.hint"] = "Staff boosts the floor they work on.",

		-- Facade
		["tui.facade.skins"] = "Facades",
		["tui.facade.pass"] = "Facade pass",
		["tui.facade.neon"] = "Neon colour",
		["tui.facade.crown"] = "Crown",
		["tui.facade.noCrown"] = "No crown",
		["tui.facade.name"] = "Tower name",
		["tui.facade.adj"] = "Word 1",
		["tui.facade.noun"] = "Word 2",
		["tui.facade.apply"] = "Apply",
		["tui.facade.layout"] = "Floor plan",
		["tui.facade.layoutHint"] = "Keep the floor plan after the IPO",
		["tui.facade.private"] = "Private floors: %s/%s",
		["tui.skinHint.Obsidian"] = "Login calendar day 14",
		["tui.skinHint.MarbleWhite"] = "Unlock an achievement",
		["tui.skinHint.NeonCyber"] = "Unlock an achievement",
		["tui.skinHint.HoloPrism"] = "Skyline Pass premium",
		["tui.skinHint.Polar"] = "Login calendar day 28",

		-- Visit
		["tui.visit.title"] = "Visit towers",
		["tui.visit.none"] = "No other tower is occupied right now.",
		["tui.visit.you"] = " (you)",
		["tui.visit.go"] = "Visit",
		["tui.visit.home"] = "Go home",

		-- Elevator & prompts
		["tui.elevator.title"] = "Elevator",
		["tui.elevator.lobby"] = "G",
		["tui.elevator.private"] = "This floor is private.",
		["tui.elevator.notInside"] = "The elevator only runs inside a tower.",
		["tui.elevator.prompt"] = "Elevator",
		["tui.respekt.prompt"] = "Give respect",
		["tui.help.prompt"] = "Help build",
		["tui.crane"] = "Floor %s under construction · %s",

		-- Effects
		["tui.fx.perSec"] = "+%s/s",
		["tui.fx.stage"] = "Stage %s: %s",
		["tui.fx.credits"] = "+%s",

		-- Welcome back
		["tui.welcome.title"] = "Welcome back",
		["tui.welcome.away"] = "You were away for %s. Here is what happened:",
		["tui.welcome.before"] = "Before",
		["tui.welcome.after"] = "Now",
		["tui.welcome.offline"] = "Tower offline +%s (%d %% for %s)",
		["tui.welcome.dividends"] = "Dividends +%s",
		["tui.welcome.fills"] = "%d orders filled",
		["tui.welcome.alerts"] = "%d alerts triggered",
		["tui.welcome.bot"] = "Bot “%s”: %s",
		["tui.welcome.built"] = "%s floor(s) finished",
		["tui.welcome.transfer"] = "Auto transfer +%s",
		["tui.welcome.quiet"] = "All quiet – your tower waited for you.",
		["tui.welcome.collect"] = "Collect",
		["tui.welcome.credited"] = "Already credited – this is just the summary.",

		-- Future self
		["tui.future.title"] = "Your future self",
		["tui.future.income"] = "In %d h your tower earns ≈ %s",
		["tui.future.orders"] = "%d protective orders watch your portfolio",
		["tui.future.noOrders"] = "Tip: stop orders protect your portfolio while you are away",
		["tui.future.build"] = "Floor %s ready in %s",
	},
}
