-- =====================================================================
--  AKYTEX TYCOON – Texte "life." (Shared/Lang/Life)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Nur Schlüssel mit Präfix "life.". Vertrag: DESIGN.md §C15,
--  §B12 (Uhren, Accessoires – jugendfrei), §B4.8 (Deko-Lager), §B9.6 (Vorstand „Lifestyle“), §D WP8 (Boutique).
--  Platzhalter wie string.format: %s = Text (auch fertig formatierte CR-Beträge), %d = ganze Zahl, %% = Prozent.
--  Teil-Namen stehen in Config.Lifestyle / Config.Decor ({ de, en }), nicht hier.
--  Sätze kurz und ruhig, keine Wett-/Glücksspiel-Wörter (Wortliste §0.7, Vertrags-Prüfer BANNED_WORDS).
--  Dynamische Schlüssel: life.tab.<showcase|watches|accessories|decor|storage>, life.kind.<Watch|Accessory|Decor>,
--  life.attach.<Head|Torso|RightHand|Root>, life.src.<Quelle>, life.sourceOpen.<Pass|Starter|Season|Login>,
--  life.state.<worn|owned|stored|placed|locked>.
-- =====================================================================

return {
	de = {
		-- Server-Antworten (LifestyleService)
		["life.owned"] = "Das gehört dir schon.",
		["life.notOwned"] = "Das besitzt du noch nicht.",
		["life.notForSale"] = "Dieses Teil gibt es nicht zu kaufen.",
		["life.noCredits"] = "Nicht genug CR – es fehlen %s",
		["life.shopMissing"] = "Das CR-Konto ist gerade nicht erreichbar – gleich nochmal",
		["life.storageFull"] = "Lager voll – höchstens %d Stück je Teil",
		["life.boughtWorn"] = "%s gekauft – tippe „Tragen“",
		["life.boughtDecor"] = "%s liegt jetzt in deinem Lager",
		["life.watchOn"] = "%s am Handgelenk",
		["life.watchOff"] = "Uhr abgelegt",
		["life.accOn"] = "%s angelegt",
		["life.accOff"] = "%s abgelegt",
		["life.accCleared"] = "Alle Accessoires abgelegt",
		["life.accFull"] = "Höchstens %d Accessoires gleichzeitig",
		-- Neon-Jetpack (Pass)
		["life.jet.noPass"] = "Das Neon-Jetpack gibt es mit dem Pass „Neon-Jetpack“",
		["life.jet.seated"] = "Erst aussteigen, dann abheben",
		["life.jet.foreign"] = "In fremden Towern bleibt das Jetpack aus",
		["life.jet.recharge"] = "Jetpack lädt noch – %d s",
		["life.jet.empty"] = "Jetpack leer – lädt am Boden nach",
		["life.jet.hint"] = "Neon-Jetpack bereit: in der Luft nochmal springen und gedrückt halten",
		["life.jet.label"] = "JETPACK",

		-- Fenster & Tabs
		["life.title"] = "Chronohaus",
		["life.tab.showcase"] = "Auslage",
		["life.tab.watches"] = "Uhren",
		["life.tab.accessories"] = "Accessoires",
		["life.tab.decor"] = "Deko",
		["life.tab.storage"] = "Lager",
		["life.preview"] = "Tippe ein Teil an",
		["life.pickHint"] = "Wähle ein Teil – die große Vorschau zeigt es von allen Seiten.",
		["life.busy"] = "Einen Moment …",
		["life.new"] = "NEU",

		-- Auslage (4-h-Rotation)
		["life.showcase.title"] = "Aktuelle Auslage",
		["life.rotationEnds"] = "Neue Auslage in %s",
		["life.rotationSoon"] = "Neue Auslage kommt gleich",
		["life.rotationEmpty"] = "Die Auslage wird gerade neu eingeräumt.",
		["life.inShowcase"] = "In der Auslage",
		["life.discount"] = "Vorstand-Rabatt −%d %% auf Uhren und Deko",

		-- Arten & Plätze
		["life.kind.Watch"] = "Uhr",
		["life.kind.Accessory"] = "Accessoire",
		["life.kind.Decor"] = "Deko",
		["life.wrist"] = "Linkes Handgelenk",
		["life.attach.Head"] = "Kopf",
		["life.attach.Torso"] = "Brust",
		["life.attach.RightHand"] = "Rechte Hand",
		["life.attach.Root"] = "Boden-Aura",
		["life.comfort"] = "Komfort +%d",

		-- Preise & Knöpfe
		["life.price"] = "Preis %s",
		["life.priceDiscount"] = "Preis %s (statt %s)",
		["life.balance"] = "Dein Guthaben: %s",
		["life.missing"] = "Es fehlen noch %s",
		["life.buy"] = "Kaufen · %s",
		["life.buyMore"] = "Noch eins · %s",
		["life.buyConfirm"] = "Sicher? Nochmal tippen · %s",
		["life.wear"] = "Tragen",
		["life.takeOff"] = "Ablegen",
		["life.place"] = "Im Tower platzieren",
		["life.accFullShort"] = "Schon %d getragen",

		-- Status
		["life.state.worn"] = "Getragen",
		["life.state.owned"] = "Im Besitz",
		["life.state.stored"] = "Im Lager: %d",
		["life.state.placed"] = "Platziert: %d",
		["life.state.locked"] = "Nicht im Verkauf",
		["life.inStorage"] = "Im Lager: %d · platziert: %d",

		-- Quellen nicht kaufbarer Teile
		["life.src.Licence"] = "Kommt mit der Lizenz „%s“",
		["life.src.Perk"] = "Vorstand „%s“ Stufe %d",
		["life.src.Pass"] = "Teil der Chrono-Kollektion (Pass)",
		["life.src.Starter"] = "Im Starter-Paket enthalten",
		["life.src.Season"] = "Belohnung im Skyline-Pass",
		["life.src.Login"] = "Belohnung im Login-Kalender",
		["life.src.League"] = "Pokal aus der Liga",
		["life.src.Group"] = "Für Mitglieder der Gruppe „AKYTEX Games“",
		["life.src.Other"] = "Wird freigeschaltet",
		["life.licenceN"] = "Lizenz %d",
		["life.sourceOpen.Pass"] = "Pass ansehen",
		["life.sourceOpen.Starter"] = "Starter-Paket ansehen",
		["life.sourceOpen.Season"] = "Zum Skyline-Pass",
		["life.sourceOpen.Login"] = "Zum Login-Kalender",

		-- Uhren & Accessoires
		["life.onWrist"] = "Am Handgelenk: %s",
		["life.noWatch"] = "Gerade keine Uhr am Handgelenk",
		["life.watchHint"] = "Alle sehen deine Uhr – die Zeiger zeigen die Stadtzeit.",
		["life.accCount"] = "Accessoires getragen: %d/%d",
		["life.accClear"] = "Alle ablegen",
		["life.noAcc"] = "Keine Accessoires angelegt",

		-- Lager
		["life.storage.title"] = "Dein Lager",
		["life.storage.summary"] = "Im Lager: %d · im Tower platziert: %d",
		["life.storage.empty"] = "Noch keine Deko – im Tab „Deko“ findest du 6 Sets.",
		["life.collection"] = "Sammlungswert ≈ %s",
		["life.worn.title"] = "Am Körper",
	},
	en = {
		-- Server replies (LifestyleService)
		["life.owned"] = "You already own this.",
		["life.notOwned"] = "You don't own this yet.",
		["life.notForSale"] = "This item is not for sale.",
		["life.noCredits"] = "Not enough CR – %s missing",
		["life.shopMissing"] = "The CR account is unavailable right now – try again shortly",
		["life.storageFull"] = "Storage full – at most %d per item",
		["life.boughtWorn"] = "%s bought – tap “Wear”",
		["life.boughtDecor"] = "%s is now in your storage",
		["life.watchOn"] = "%s on your wrist",
		["life.watchOff"] = "Watch taken off",
		["life.accOn"] = "%s put on",
		["life.accOff"] = "%s taken off",
		["life.accCleared"] = "All accessories taken off",
		["life.accFull"] = "At most %d accessories at once",
		-- Neon jetpack (pass)
		["life.jet.noPass"] = "The neon jetpack comes with the “Neon Jetpack” pass",
		["life.jet.seated"] = "Get out of the car first, then take off",
		["life.jet.foreign"] = "The jetpack stays off inside other players' towers",
		["life.jet.recharge"] = "Jetpack still recharging – %d s",
		["life.jet.empty"] = "Jetpack empty – it recharges on the ground",
		["life.jet.hint"] = "Neon jetpack ready: jump again in mid-air and hold",
		["life.jet.label"] = "JETPACK",

		-- Window & tabs
		["life.title"] = "Chronohaus",
		["life.tab.showcase"] = "Showcase",
		["life.tab.watches"] = "Watches",
		["life.tab.accessories"] = "Accessories",
		["life.tab.decor"] = "Decor",
		["life.tab.storage"] = "Storage",
		["life.preview"] = "Tap an item",
		["life.pickHint"] = "Pick an item – the big preview shows it from every side.",
		["life.busy"] = "One moment …",
		["life.new"] = "NEW",

		-- Showcase (4 h rotation)
		["life.showcase.title"] = "Current showcase",
		["life.rotationEnds"] = "New showcase in %s",
		["life.rotationSoon"] = "New showcase coming up",
		["life.rotationEmpty"] = "The showcase is being restocked.",
		["life.inShowcase"] = "In the showcase",
		["life.discount"] = "Board discount −%d %% on watches and decor",

		-- Kinds & spots
		["life.kind.Watch"] = "Watch",
		["life.kind.Accessory"] = "Accessory",
		["life.kind.Decor"] = "Decor",
		["life.wrist"] = "Left wrist",
		["life.attach.Head"] = "Head",
		["life.attach.Torso"] = "Chest",
		["life.attach.RightHand"] = "Right hand",
		["life.attach.Root"] = "Floor aura",
		["life.comfort"] = "Comfort +%d",

		-- Prices & buttons
		["life.price"] = "Price %s",
		["life.priceDiscount"] = "Price %s (instead of %s)",
		["life.balance"] = "Your balance: %s",
		["life.missing"] = "%s still missing",
		["life.buy"] = "Buy · %s",
		["life.buyMore"] = "One more · %s",
		["life.buyConfirm"] = "Sure? Tap again · %s",
		["life.wear"] = "Wear",
		["life.takeOff"] = "Take off",
		["life.place"] = "Place in tower",
		["life.accFullShort"] = "%d already worn",

		-- Status
		["life.state.worn"] = "Worn",
		["life.state.owned"] = "Owned",
		["life.state.stored"] = "Stored: %d",
		["life.state.placed"] = "Placed: %d",
		["life.state.locked"] = "Not for sale",
		["life.inStorage"] = "Stored: %d · placed: %d",

		-- Sources of items that can't be bought
		["life.src.Licence"] = "Comes with the “%s” licence",
		["life.src.Perk"] = "Board “%s” level %d",
		["life.src.Pass"] = "Part of the Chrono collection (pass)",
		["life.src.Starter"] = "Included in the starter pack",
		["life.src.Season"] = "Reward in the Skyline Pass",
		["life.src.Login"] = "Reward in the login calendar",
		["life.src.League"] = "League trophy",
		["life.src.Group"] = "For members of the “AKYTEX Games” group",
		["life.src.Other"] = "Unlocks later",
		["life.licenceN"] = "Licence %d",
		["life.sourceOpen.Pass"] = "View pass",
		["life.sourceOpen.Starter"] = "View starter pack",
		["life.sourceOpen.Season"] = "Open Skyline Pass",
		["life.sourceOpen.Login"] = "Open login calendar",

		-- Watches & accessories
		["life.onWrist"] = "On your wrist: %s",
		["life.noWatch"] = "No watch on your wrist right now",
		["life.watchHint"] = "Everyone sees your watch – the hands show city time.",
		["life.accCount"] = "Accessories worn: %d/%d",
		["life.accClear"] = "Take all off",
		["life.noAcc"] = "No accessories on",

		-- Storage
		["life.storage.title"] = "Your storage",
		["life.storage.summary"] = "Stored: %d · placed in tower: %d",
		["life.storage.empty"] = "No decor yet – the “Decor” tab has 6 sets.",
		["life.collection"] = "Collection value ≈ %s",
		["life.worn.title"] = "Worn",
	},
}
