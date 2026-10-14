-- =====================================================================
--  AKYTEX TYCOON – Texte "tower." (Shared/Lang/Tower)
--  Besitzer: WP6 (Turm-Ökonomie). Nur Schlüssel mit Präfix "tower.". Vertrag: DESIGN.md §C15, §B4, §B5, §B8.2.
--  Platzhalter wie string.format: %s = Text, %d = ganze Zahl, %% = Prozentzeichen. CR-Beträge kommen fertig
--  formatiert als %s (Format.Credits). Namen von Stufen/Abteilungen/Personal stehen in Config.Tower ({ de, en }).
--  Sätze kurz und ruhig, keine Wett-/Glücksspiel-Wörter (Wortliste §0.7, Vertrags-Prüfer BANNED_WORDS).
--  Pflicht (§C15): tower.vaultFull, tower.maxMoney.
-- =====================================================================

return {
	de = {
		-- Pflicht
		["tower.vaultFull"] = "Tresor voll – einsammeln!",
		["tower.maxMoney"] = "Tresor am Limit – Zeit für den Börsengang!",

		-- Bauen
		["tower.craneBusy"] = "Der Kran baut noch – fertig in %s",
		["tower.maxFloors"] = "Alle 50 Etagen stehen – Zeit für den Börsengang!",
		["tower.noCredits"] = "Nicht genug CR – es fehlen %s CR",
		["tower.gateLicence"] = "%s braucht die Lizenz %s",
		["tower.gateIpo"] = "%s braucht mindestens %d Börsengang",
		["tower.stageAnnounce"] = "%s erreicht Stufe %d: %s!",
		["tower.noFloor"] = "Diese Etage gibt es noch nicht",
		["tower.noPlot"] = "Du hast gerade keinen Bauplatz",
		["tower.shopMissing"] = "Das CR-Konto ist gerade nicht erreichbar – gleich nochmal",

		-- Abteilungen & Raum-Stufen
		["tower.roomSet"] = "Etage %d ist jetzt: %s",
		["tower.roomSame"] = "Diese Etage hat diese Abteilung schon",
		["tower.roomLocked"] = "%s gibt es ab Stufe %d",
		["tower.roomTopOnly"] = "Das Penthouse geht nur auf der obersten Etage",
		["tower.roomMax"] = "Höchstens %d × %s im Tower",
		["tower.levelUp"] = "Etage %d: Raum-Stufe L%d",
		["tower.levelMax"] = "Höchste Raum-Stufe erreicht",

		-- Personal
		["tower.hired"] = "%s arbeitet jetzt auf Etage %d",
		["tower.lobbyHired"] = "%s ist jetzt in deiner Lobby",
		["tower.staffLocked"] = "%s gibt es ab Stufe %d",
		["tower.slotsFull"] = "Alle Plätze auf Etage %d sind besetzt",
		["tower.slotsPlus"] = "Etage %d ist voll – mit Personal+ gibt es einen 3. Platz",
		["tower.fired"] = "%s hat den Tower verlassen",
		["tower.noStaff"] = "Auf diesem Platz arbeitet niemand",
		["tower.uniqueOwned"] = "Den hast du schon – einer je Tower",

		-- Effizienz
		["tower.effUp"] = "Effizienz-Stufe %d – Multiplikator jetzt %s",
		["tower.effMax"] = "Alle 20 Effizienz-Stufen gekauft",

		-- Tresor & Offline
		["tower.vaultEmpty"] = "Der Tresor ist leer",
		["tower.tooFar"] = "Geh näher an deinen Tower (höchstens %d Studs)",
		["tower.offline"] = "Dein Tower hat offline %s CR verdient",
		["tower.boostEnded"] = "Boost %s ist abgelaufen",
		["tower.boostResumed"] = "Boost %s ist abgelaufen – %s läuft weiter (noch %s)",

		-- Gewinn-Transfer
		["tower.transferDone"] = "Gewinn-Transfer: +%s CR für deinen Tower",
		["tower.transferBell"] = "Auto-Transfer an der Glocke: +%s CR",

		-- Sofortbau & Bau-Express
		["tower.dailyToken"] = "Neuer Gratis-Sofortbau-Token für heute",
		["tower.instantUsed"] = "Sofortbau! Etage %d ist fertig",
		["tower.noInstant"] = "Kein Sofortbau-Token übrig",
		["tower.noBuild"] = "Gerade läuft kein Bau",
		["tower.instantNotNeeded"] = "Diese Etage ist gleich fertig",
		["tower.expressUsed"] = "Bau-Express: %s schneller",
		["tower.noExpress"] = "Kein Bau-Express-Token übrig",

		-- Bau-Hilfe
		["tower.helped"] = "Danke! Du hast beim Bau geholfen (−10 %% Restzeit)",
		["tower.helpReceived"] = "%s hilft beim Bau: −10 %% Restzeit",
		["tower.helpFull"] = "Hier helfen schon 3 – der Kran ist voll besetzt",
		["tower.helpAgain"] = "Bei dieser Etage hast du schon geholfen",
		["tower.helpSelf"] = "Bei deinem eigenen Bau hilft dir der Kran",
		["tower.helpTooFar"] = "Geh näher an die Baustelle",
		["tower.helpNew"] = "Bau-Hilfe ab 3 Tagen Konto-Alter und 10 Minuten Spielzeit",
		["tower.ownerGone"] = "Dieser Spieler ist nicht mehr da",

		-- Besuche & Aufzug
		["tower.visiting"] = "Willkommen im Tower von %s",
		["tower.home"] = "Zurück in deinem Tower",
		["tower.inCar"] = "Steig erst aus dem Auto",
		["tower.noCharacter"] = "Gerade nicht möglich – gleich nochmal",
		["tower.notInTower"] = "Der Aufzug fährt nur im Tower",
		["tower.privateFloor"] = "Diese Etage ist privat",

		-- Name, Fassade, Neon, Privat-Etagen
		["tower.nameSet"] = "Neuer Tower-Name: %s",
		["tower.skinSet"] = "Fassade: %s",
		["tower.neonSet"] = "Neon: %s",
		["tower.locked"] = "Noch nicht freigeschaltet",
		["tower.privateOn"] = "Etage %d ist jetzt privat",
		["tower.privateOff"] = "Etage %d ist wieder offen",
		["tower.privateMax"] = "Höchstens %d private Etagen",

		-- Deko & Layout
		["tower.decorPlaced"] = "Deko steht jetzt auf Etage %d",
		["tower.decorRemoved"] = "Deko zurück ins Lager (Etage %d)",
		["tower.decorNone"] = "Davon hast du nichts im Lager",
		["tower.decorSame"] = "Das steht hier schon",
		["tower.decorUnavailable"] = "Deko ist gerade nicht verfügbar",
		["tower.layoutOn"] = "Layout merken: an",
		["tower.layoutOff"] = "Layout merken: aus",

		-- Auto-Plan (Tiko)
		["tower.autoPlan"] = "Tikos Vorschlag bringt +%s CR/s",
		["tower.autoPlanNone"] = "Deine Belegung ist schon top",
	},
	en = {
		-- Required
		["tower.vaultFull"] = "Vault full – collect it!",
		["tower.maxMoney"] = "Vault at the limit – time for your IPO!",

		-- Building
		["tower.craneBusy"] = "The crane is still building – done in %s",
		["tower.maxFloors"] = "All 50 floors are built – time for your IPO!",
		["tower.noCredits"] = "Not enough CR – %s CR missing",
		["tower.gateLicence"] = "%s needs the %s licence",
		["tower.gateIpo"] = "%s needs at least %d IPO",
		["tower.stageAnnounce"] = "%s reached stage %d: %s!",
		["tower.noFloor"] = "That floor does not exist yet",
		["tower.noPlot"] = "You have no plot right now",
		["tower.shopMissing"] = "Your CR account is not reachable right now – try again",

		-- Departments & room levels
		["tower.roomSet"] = "Floor %d is now: %s",
		["tower.roomSame"] = "This floor already has that department",
		["tower.roomLocked"] = "%s unlocks at stage %d",
		["tower.roomTopOnly"] = "The penthouse only fits on the top floor",
		["tower.roomMax"] = "At most %d × %s per tower",
		["tower.levelUp"] = "Floor %d: room level L%d",
		["tower.levelMax"] = "Highest room level reached",

		-- Staff
		["tower.hired"] = "%s now works on floor %d",
		["tower.lobbyHired"] = "%s is now in your lobby",
		["tower.staffLocked"] = "%s unlocks at stage %d",
		["tower.slotsFull"] = "All slots on floor %d are taken",
		["tower.slotsPlus"] = "Floor %d is full – Staff+ adds a 3rd slot",
		["tower.fired"] = "%s left the tower",
		["tower.noStaff"] = "Nobody works in this slot",
		["tower.uniqueOwned"] = "You already have one – one per tower",

		-- Efficiency
		["tower.effUp"] = "Efficiency level %d – multiplier now %s",
		["tower.effMax"] = "All 20 efficiency levels bought",

		-- Vault & offline
		["tower.vaultEmpty"] = "The vault is empty",
		["tower.tooFar"] = "Move closer to your tower (at most %d studs)",
		["tower.offline"] = "Your tower earned %s CR while you were away",
		["tower.boostEnded"] = "Boost %s has ended",
		["tower.boostResumed"] = "Boost %s has ended – %s continues (%s left)",

		-- Profit transfer
		["tower.transferDone"] = "Profit transfer: +%s CR for your tower",
		["tower.transferBell"] = "Auto transfer at the bell: +%s CR",

		-- Instant build & build express
		["tower.dailyToken"] = "New free instant-build token for today",
		["tower.instantUsed"] = "Instant build! Floor %d is done",
		["tower.noInstant"] = "No instant-build token left",
		["tower.noBuild"] = "Nothing is being built right now",
		["tower.instantNotNeeded"] = "This floor is almost done",
		["tower.expressUsed"] = "Build express: %s faster",
		["tower.noExpress"] = "No build-express token left",

		-- Build help
		["tower.helped"] = "Thanks! You helped with the build (−10%% time left)",
		["tower.helpReceived"] = "%s is helping you build: −10%% time left",
		["tower.helpFull"] = "Three helpers already – the crane is fully staffed",
		["tower.helpAgain"] = "You already helped with this floor",
		["tower.helpSelf"] = "The crane is your helper on your own build",
		["tower.helpTooFar"] = "Move closer to the construction site",
		["tower.helpNew"] = "Build help needs a 3-day-old account and 10 minutes of play",
		["tower.ownerGone"] = "That player is no longer here",

		-- Visits & elevator
		["tower.visiting"] = "Welcome to %s's tower",
		["tower.home"] = "Back in your tower",
		["tower.inCar"] = "Leave your car first",
		["tower.noCharacter"] = "Not possible right now – try again",
		["tower.notInTower"] = "The elevator only runs inside a tower",
		["tower.privateFloor"] = "This floor is private",

		-- Name, facade, neon, private floors
		["tower.nameSet"] = "New tower name: %s",
		["tower.skinSet"] = "Facade: %s",
		["tower.neonSet"] = "Neon: %s",
		["tower.locked"] = "Not unlocked yet",
		["tower.privateOn"] = "Floor %d is now private",
		["tower.privateOff"] = "Floor %d is open again",
		["tower.privateMax"] = "At most %d private floors",

		-- Decor & layout
		["tower.decorPlaced"] = "Decor placed on floor %d",
		["tower.decorRemoved"] = "Decor back in storage (floor %d)",
		["tower.decorNone"] = "You have none of these in storage",
		["tower.decorSame"] = "That is already here",
		["tower.decorUnavailable"] = "Decor is not available right now",
		["tower.layoutOn"] = "Remember layout: on",
		["tower.layoutOff"] = "Remember layout: off",

		-- Auto plan (Tiko)
		["tower.autoPlan"] = "Tiko's plan adds +%s CR/s",
		["tower.autoPlanNone"] = "Your layout is already top",
	},
}
