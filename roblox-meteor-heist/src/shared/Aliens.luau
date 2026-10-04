--!strict
-- =====================================================================
--  METEOR HEIST – ALIENS
--  Aus jedem Meteor schlüpft nach der Schlüpfzeit ein Alien.
--  Pro Meteor gibt es GENAU 3 mögliche Aliens:
--    1. Zeile = "Normal"  (75% Chance, Einkommen x1)
--    2. Zeile = "Selten"  (22% Chance, Einkommen x2.5)
--    3. Zeile = "Ultra"   ( 3% Chance, Einkommen x6)
--  Glück (Server-Glück, Meteoritenschauer) macht Selten + Ultra wahrscheinlicher.
--
--  Neue Aliens? Einfach die Zeilen unten ändern. Spalten einer Zeile:
--    { Id, Name, Form, Farbe, Akzentfarbe, Augen, Antennen, [Extras] }
--    Id     = einmalig, nie wieder ändern (steht in den Spielständen!)
--    Form   = Blob, Cyclops, Squid, Bug, Robot, Ghost, Crystal, Spiky, King, Mushroom
--    Augen  = 1 bis 4, Antennen = 0 bis 3
--    Extras = optional, z.B. { Scale = 1.1, Effects = { Rainbow = true } }
--             (oder unten in der Tabelle EXTRAS unter der Alien-Id eintragen)
--  Effekte (Aura, Licht) kommen automatisch nach Seltenheit + Stufe.
--  Umriss (Highlight) gibt es nur noch bei Ultra-Aliens der Seltenheit "Admin"
--  (Roblox zeigt nur ~31 Highlights gleichzeitig – sonst überall anders ignoriert).
--  Mutationen (Gold, Diamond, Galaxy, Frost, Lava, Rainbow) färben jedes Alien automatisch
--  um (AlienFactory) – dafür muss hier nichts eingetragen werden.
--
--  WICHTIG: Diese Datei darf Config NICHT laden (Config lädt diese Datei).
--  Die Seltenheiten-Namen müssen genau wie in Config.Rarities heißen.
-- =====================================================================

export type AlienLook = {
	Archetype: string,
	Color: Color3,
	Accent: Color3,
	Eyes: number,
	Antennas: number,
	Scale: number,
}

export type AlienEffects = {
	Rainbow: boolean?,
	Aura: boolean?,
	Highlight: boolean?, -- wirkt nur bei Tier "Ultra" + Rarity "Admin" (AlienFactory)
	BigLight: boolean?,
	Fire: boolean?,
}

export type AlienDef = {
	Id: string,
	Name: string,
	Meteor: string,
	Rarity: string,
	Tier: string,
	Weight: number,
	IncomeMult: number,
	Look: AlienLook,
	Effects: AlienEffects,
	Order: number,
}

export type RollOption = { Id: string, Weight: number }

export type Chance = { Id: string, Name: string, Tier: string, Chance: number }

type Row = { any }

local rgb = Color3.fromRGB

local Aliens = {
	List = {} :: { AlienDef },
	ById = {} :: { [string]: AlienDef },
	ByMeteor = {} :: { [string]: { RollOption } },
	MeteorOrder = {} :: { string },
	Count = 0,

	-- Die 3 Stufen (Reihenfolge = Zeilen-Reihenfolge pro Meteor)
	Tiers = {
		{ Name = "Normal", Weight = 75, IncomeMult = 1 },
		{ Name = "Selten", Weight = 22, IncomeMult = 2.5 },
		{ Name = "Ultra", Weight = 3, IncomeMult = 6 },
	},
	TierColors = {
		Normal = rgb(235, 235, 235),
		Selten = rgb(80, 200, 255),
		Ultra = rgb(255, 80, 230),
	} :: { [string]: Color3 },

	-- Alle Körperformen, die die AlienFactory bauen kann
	Archetypes = { "Blob", "Cyclops", "Squid", "Bug", "Robot", "Ghost", "Crystal", "Spiky", "King", "Mushroom" },

	-- Rang jeder Seltenheit (gleiche Reihenfolge wie Config.Rarities)
	RarityRank = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
		Mythic = 6,
		Celestial = 7,
		Divine = 8,
		Secret = 9,
		Godly = 10,
		Cosmic = 11,
		Infinity = 12,
		Admin = 13,
	} :: { [string]: number },
}

-- Größe nach Seltenheit (1 = normal). Footprint bleibt auch bei Level 20 auf einem 8x8-Pad.
local RARITY_SCALE: { [string]: number } = {
	Common = 0.85,
	Uncommon = 0.92,
	Rare = 1.0,
	Epic = 1.08,
	Legendary = 1.16,
	Mythic = 1.24,
	Celestial = 1.32,
	Divine = 1.4,
	Secret = 1.5,
	Godly = 1.58,
	Cosmic = 1.66,
	Infinity = 1.75,
	Admin = 2.0,
}
local TIER_SCALE = { 1, 1.06, 1.12 }

local MAX_LUCK = 1000 -- Schutz gegen unsinnige Glückswerte
local RNG = Random.new()

-- Extras für einzelne Aliens (überschreiben die Automatik). Alternativ als 8. Spalte in der Zeile.
local EXTRAS: { [string]: { [string]: any } } = {
	BigBangKing = { Effects = { Rainbow = true } },
	MultiverseSquid = { Effects = { Rainbow = true } },
}

local archetypeSet: { [string]: boolean } = {}
for _, name in ipairs(Aliens.Archetypes) do
	archetypeSet[name] = true
end
local namesTaken: { [string]: string } = {}

-- Effekte automatisch nach Seltenheit + Stufe (sparsam, damit nichts laggt).
-- Umriss (Highlight) nur bei Ultra + Admin: Roblox zeigt höchstens ~31 Highlights gleichzeitig.
-- Godly+ (über Secret): Selten bekommt starkes Licht, Infinity-Ultra leuchtet in Regenbogenfarben.
local function autoEffects(rank: number, tierIndex: number): AlienEffects
	local fx: AlienEffects = {}
	local ranks = Aliens.RarityRank
	if rank >= ranks.Admin then
		-- Admin: alles krass
		fx.Aura = true
		fx.BigLight = true
		if tierIndex == 3 then
			fx.Rainbow = true
			fx.Highlight = true
		end
	elseif tierIndex == 3 then
		if rank >= 3 then
			fx.Aura = true
		end
		if rank >= 8 then
			fx.BigLight = true
		end
		if rank >= ranks.Infinity then
			fx.Rainbow = true
		end
	elseif tierIndex == 2 then
		if rank >= 7 then
			fx.Aura = true
		end
		if rank >= ranks.Godly then
			fx.BigLight = true
		end
	elseif rank >= 9 then
		fx.Aura = true
	end
	return fx
end

local function clampInt(value: any, min: number, max: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value), min, max)
end

-- Fügt die 3 Aliens eines Meteors hinzu. extraEffects gilt für alle 3 (z.B. Regenbogen-Meteor).
local function add(meteorId: string, rarity: string, rows: { Row }, extraEffects: AlienEffects?)
	assert(Aliens.ByMeteor[meteorId] == nil, "[Aliens] Meteor doppelt: " .. meteorId)
	assert(#rows == #Aliens.Tiers, "[Aliens] " .. meteorId .. " braucht genau 3 Aliens")
	local rank = Aliens.RarityRank[rarity]
	if not rank then
		warn("[Aliens] Unbekannte Seltenheit '" .. tostring(rarity) .. "' bei " .. meteorId)
		rank = 1
	end
	local options: { RollOption } = {}
	for tierIndex, row in ipairs(rows) do
		local tier = Aliens.Tiers[tierIndex]
		local id = row[1] :: string
		local name = row[2] :: string
		local archetype = row[3] :: string
		local extras = (row[8] or EXTRAS[id] or {}) :: { [string]: any }
		assert(type(id) == "string" and id ~= "", "[Aliens] Id fehlt bei " .. meteorId)
		assert(Aliens.ById[id] == nil, "[Aliens] Doppelte Alien-Id: " .. id)
		assert(type(name) == "string" and name ~= "", "[Aliens] Name fehlt bei " .. id)
		assert(namesTaken[name] == nil, "[Aliens] Doppelter Name '" .. name .. "' (" .. id .. ")")
		if not archetypeSet[archetype] then
			warn("[Aliens] Unbekannte Form '" .. tostring(archetype) .. "' bei " .. id .. " -> Blob")
			archetype = "Blob"
		end

		local fx = autoEffects(rank, tierIndex)
		for key, value in pairs(extraEffects or {}) do
			(fx :: any)[key] = value
		end
		if type(extras.Effects) == "table" then
			for key, value in pairs(extras.Effects) do
				(fx :: any)[key] = value
			end
		end

		local scale = (RARITY_SCALE[rarity] or 1) * TIER_SCALE[tierIndex]
		if type(extras.Scale) == "number" and extras.Scale > 0 then
			scale *= extras.Scale
		end

		local def: AlienDef = {
			Id = id,
			Name = name,
			Meteor = meteorId,
			Rarity = rarity,
			Tier = tier.Name,
			Weight = tier.Weight,
			IncomeMult = tier.IncomeMult,
			Look = {
				Archetype = archetype,
				Color = typeof(row[4]) == "Color3" and row[4] or rgb(200, 200, 200),
				Accent = typeof(row[5]) == "Color3" and row[5] or rgb(255, 255, 255),
				Eyes = clampInt(row[6], 1, 4, 2),
				Antennas = clampInt(row[7], 0, 3, 0),
				Scale = scale,
			},
			Effects = fx,
			Order = #Aliens.List + 1,
		}
		namesTaken[name] = id
		table.insert(Aliens.List, def)
		Aliens.ById[id] = def
		table.insert(options, { Id = id, Weight = tier.Weight })
	end
	Aliens.ByMeteor[meteorId] = options
	table.insert(Aliens.MeteorOrder, meteorId)
end

-- =====================================================================
--  DIE ALIENS (pro Meteor: Normal, Selten, Ultra)
--  { Id, Name, Form, Farbe, Akzentfarbe, Augen, Antennen, [Extras] }
-- =====================================================================

-- COMMON -------------------------------------------------------------
add("Pebble", "Common", {
	{ "PebbleBlob", "Kiesel-Blobby", "Blob", rgb(178, 184, 200), rgb(255, 190, 120), 2, 1 },
	{ "PebbleBug", "Steinkäfer Kurt", "Bug", rgb(128, 136, 156), rgb(255, 170, 60), 2, 2 },
	{ "PebbleKing", "König Kieselstein", "King", rgb(196, 198, 210), rgb(220, 50, 75), 2, 0 },
})
add("Dusty", "Common", {
	{ "DustyGhost", "Staubi Puff", "Ghost", rgb(232, 208, 172), rgb(190, 130, 80), 2, 0 },
	{ "DustyMushroom", "Krümel-Pilz", "Mushroom", rgb(196, 132, 84), rgb(255, 240, 210), 2, 0 },
	{ "DustyRobot", "Sandsturm-Bot 3000", "Robot", rgb(214, 164, 98), rgb(255, 140, 40), 2, 1 },
})
add("Ember", "Common", {
	{ "EmberBlob", "Glut-Glibber", "Blob", rgb(220, 100, 50), rgb(255, 220, 80), 2, 0 },
	{ "EmberSpiky", "Feuer-Igel Fritz", "Spiky", rgb(200, 80, 40), rgb(255, 200, 60), 2, 0 },
	{ "EmberCyclops", "Funkenauge", "Cyclops", rgb(230, 90, 40), rgb(255, 240, 120), 1, 2 },
})

-- UNCOMMON -----------------------------------------------------------
add("Comet", "Uncommon", {
	{ "CometSquid", "Frosti-Tintenfisch", "Squid", rgb(170, 230, 255), rgb(255, 255, 255), 2, 0 },
	{ "CometGhost", "Brrr-Geist", "Ghost", rgb(200, 240, 255), rgb(90, 170, 255), 2, 0 },
	{ "CometCrystal", "Schneeflocki Supreme", "Crystal", rgb(150, 220, 255), rgb(230, 250, 255), 2, 0 },
})
add("Sulfur", "Uncommon", {
	{ "SulfurBug", "Stinkekäfer Stefan", "Bug", rgb(230, 220, 70), rgb(120, 110, 20), 2, 2 },
	{ "SulfurBlob", "Pupsi Gelbschleim", "Blob", rgb(240, 230, 90), rgb(160, 200, 40), 3, 2 },
	{ "SulfurCyclops", "Gasmaske Gustav", "Cyclops", rgb(220, 210, 60), rgb(90, 200, 80), 1, 1 },
})
add("Moss", "Uncommon", {
	{ "MossMushroom", "Moosbert", "Mushroom", rgb(90, 150, 60), rgb(220, 255, 160), 2, 0 },
	{ "MossSquid", "Sumpf-Sepp", "Squid", rgb(70, 130, 55), rgb(180, 230, 90), 2, 0 },
	{ "MossKing", "Waldkönig Moosimus", "King", rgb(100, 170, 70), rgb(60, 110, 40), 2, 0 },
})

-- RARE ---------------------------------------------------------------
add("Cobalt", "Rare", {
	{ "CobaltRobot", "Blechbüchse B-12", "Robot", rgb(60, 100, 210), rgb(120, 220, 255), 2, 1 },
	{ "CobaltSpiky", "Stachel-Stahl", "Spiky", rgb(40, 80, 200), rgb(200, 230, 255), 2, 0 },
	{ "CobaltCyclops", "Blauauge Bernd", "Cyclops", rgb(50, 90, 220), rgb(255, 255, 255), 1, 2 },
})
add("Magma", "Rare", {
	{ "MagmaBlob", "Lava-Lutscher", "Blob", rgb(255, 90, 30), rgb(255, 220, 60), 2, 1 },
	{ "MagmaBug", "Vulkan-Käfer", "Bug", rgb(200, 60, 20), rgb(255, 160, 0), 4, 2 },
	{ "MagmaKing", "Lavalord Brutzel", "King", rgb(255, 80, 20), rgb(120, 20, 10), 2, 0 },
})
add("Quartz", "Rare", {
	{ "QuartzCrystal", "Rosa Klunker", "Crystal", rgb(255, 150, 190), rgb(255, 220, 240), 2, 0 },
	{ "QuartzGhost", "Glitzer-Geistchen", "Ghost", rgb(255, 180, 210), rgb(255, 90, 160), 2, 0 },
	{ "QuartzSquid", "Prinzessin Pinkarm", "Squid", rgb(255, 130, 180), rgb(255, 240, 120), 3, 0 },
})

-- EPIC ---------------------------------------------------------------
add("Starlight", "Epic", {
	{ "StarlightGhost", "Sternenstaub-Sami", "Ghost", rgb(255, 250, 200), rgb(255, 220, 90), 2, 0 },
	{ "StarlightCrystal", "Funkel-Fred", "Crystal", rgb(255, 245, 180), rgb(255, 255, 255), 2, 0 },
	{ "StarlightKing", "Sternenkaiser Twinkle", "King", rgb(255, 240, 170), rgb(90, 60, 200), 2, 0 },
})
add("Plasma", "Epic", {
	{ "PlasmaSquid", "Plasma-Pulpo", "Squid", rgb(200, 80, 255), rgb(255, 150, 255), 2, 0 },
	{ "PlasmaRobot", "Zapp-O-Tron", "Robot", rgb(170, 70, 230), rgb(255, 120, 255), 3, 2 },
	{ "PlasmaBlob", "Lila Wabbel-Boss", "Blob", rgb(210, 90, 255), rgb(120, 255, 255), 3, 2 },
})
add("Thunder", "Epic", {
	{ "ThunderSpiky", "Blitz-Borsti", "Spiky", rgb(255, 235, 60), rgb(90, 90, 120), 2, 0 },
	{ "ThunderCyclops", "Donner-Dieter", "Cyclops", rgb(240, 220, 50), rgb(80, 160, 255), 1, 2 },
	{ "ThunderBug", "Gewitter-Wespe Volt", "Bug", rgb(255, 230, 40), rgb(30, 30, 40), 4, 2 },
})

-- LEGENDARY ----------------------------------------------------------
add("Solar", "Legendary", {
	{ "SolarBlob", "Sonnenschein-Sabber", "Blob", rgb(255, 180, 20), rgb(255, 90, 0), 2, 1 },
	{ "SolarCrystal", "Hitzefrei-Henry", "Crystal", rgb(255, 170, 0), rgb(255, 240, 150), 2, 0 },
	{ "SolarKing", "Sonnenkönig Ludwig", "King", rgb(255, 190, 30), rgb(230, 60, 20), 2, 0 },
})
add("Aurora", "Legendary", {
	{ "AuroraGhost", "Polarlicht-Polly", "Ghost", rgb(80, 255, 180), rgb(120, 160, 255), 2, 0 },
	{ "AuroraSquid", "Nordlicht-Krake", "Squid", rgb(60, 230, 170), rgb(200, 120, 255), 2, 0 },
	{ "AuroraCrystal", "Prisma-Queen Aurora", "Crystal", rgb(100, 255, 200), rgb(255, 140, 255), 3, 0 },
})
add("Titan", "Legendary", {
	{ "TitanRobot", "Felsbrocken-Bot", "Robot", rgb(150, 120, 104), rgb(255, 150, 40), 2, 0 },
	{ "TitanSpiky", "Granit-Grummel", "Spiky", rgb(160, 128, 112), rgb(255, 200, 120), 2, 0 },
	{ "TitanCyclops", "Titan Glotzauge", "Cyclops", rgb(170, 132, 110), rgb(255, 90, 40), 1, 0 },
})

-- MYTHIC -------------------------------------------------------------
add("Nebula", "Mythic", {
	{ "NebulaBlob", "Nebel-Nudel", "Blob", rgb(120, 50, 200), rgb(255, 120, 220), 2, 2 },
	{ "NebulaGhost", "Kosmo-Gespenst", "Ghost", rgb(140, 70, 220), rgb(90, 220, 255), 3, 0 },
	{ "NebulaKing", "Nebelfürst Nimbus", "King", rgb(110, 40, 190), rgb(255, 90, 200), 2, 0 },
})
add("BlackHole", "Mythic", {
	{ "BlackHoleSquid", "Schlürf-Schlund", "Squid", rgb(30, 10, 50), rgb(180, 80, 255), 3, 0 },
	{ "BlackHoleCyclops", "Leere-Glotzer", "Cyclops", rgb(20, 5, 40), rgb(255, 80, 255), 1, 1 },
	{ "BlackHoleRobot", "Ereignishorizont-Bot", "Robot", rgb(25, 10, 45), rgb(160, 60, 255), 3, 2 },
})
add("Pulsar", "Mythic", {
	{ "PulsarCrystal", "Ping-Pong-Pulsi", "Crystal", rgb(0, 220, 255), rgb(255, 255, 255), 2, 0 },
	{ "PulsarBug", "Puls-Käfer Beep", "Bug", rgb(0, 200, 240), rgb(255, 255, 120), 4, 2 },
	{ "PulsarSpiky", "Neutronen-Nadel", "Spiky", rgb(0, 230, 255), rgb(255, 255, 255), 2, 0 },
})

-- CELESTIAL ----------------------------------------------------------
add("Supernova", "Celestial", {
	{ "SupernovaSpiky", "Boom-Igel", "Spiky", rgb(255, 120, 40), rgb(255, 230, 80), 2, 0 },
	{ "SupernovaSquid", "Explodi-Krake", "Squid", rgb(255, 110, 30), rgb(255, 240, 120), 2, 0 },
	{ "SupernovaCyclops", "Supernova-Superauge", "Cyclops", rgb(255, 130, 50), rgb(255, 255, 200), 1, 2 },
})
add("Quasar", "Celestial", {
	{ "QuasarRobot", "Quasi-Quasar-Bot", "Robot", rgb(255, 255, 140), rgb(80, 200, 255), 2, 1 },
	{ "QuasarGhost", "Strahle-Stefanie", "Ghost", rgb(255, 255, 170), rgb(255, 170, 60), 2, 0 },
	{ "QuasarKing", "Kaiserin Quasara", "King", rgb(255, 250, 130), rgb(90, 60, 220), 2, 0 },
})
add("Galaxy", "Celestial", {
	{ "GalaxyBlob", "Milchstraßen-Matsch", "Blob", rgb(150, 90, 255), rgb(255, 255, 255), 2, 1 },
	{ "GalaxyMushroom", "Spiral-Schwammerl", "Mushroom", rgb(130, 80, 240), rgb(255, 240, 140), 2, 0 },
	{ "GalaxySquid", "Galakto-Krake Gigantus", "Squid", rgb(160, 100, 255), rgb(100, 255, 230), 3, 0 },
})

-- DIVINE -------------------------------------------------------------
add("Halo", "Divine", {
	{ "HaloGhost", "Heiligenschein-Heinz", "Ghost", rgb(255, 245, 210), rgb(255, 215, 90), 2, 0 },
	{ "HaloBug", "Engels-Marienkäfer", "Bug", rgb(255, 240, 200), rgb(255, 200, 60), 2, 2 },
	{ "HaloKing", "Erzengel Glorius", "King", rgb(255, 250, 225), rgb(255, 210, 80), 2, 0 },
})
add("Seraph", "Divine", {
	{ "SeraphCrystal", "Seraphin-Splitter", "Crystal", rgb(255, 220, 120), rgb(255, 255, 230), 2, 0 },
	{ "SeraphRobot", "Halleluja-Droid", "Robot", rgb(240, 210, 120), rgb(255, 255, 200), 2, 2 },
	{ "SeraphSpiky", "Flammenflügel Fiona", "Spiky", rgb(255, 210, 90), rgb(255, 120, 40), 2, 0 },
})
add("Eternity", "Divine", {
	{ "EternitySquid", "Ewig-Wabbler", "Squid", rgb(200, 255, 255), rgb(120, 200, 255), 2, 0 },
	{ "EternityCyclops", "Zeitlos-Zyklop", "Cyclops", rgb(190, 250, 255), rgb(255, 220, 120), 1, 1 },
	{ "EternityGhost", "Chronos der Uralte", "Ghost", rgb(210, 255, 255), rgb(160, 120, 255), 3, 0 },
})

-- SECRET -------------------------------------------------------------
add("BigBang", "Secret", {
	{ "BigBangBlob", "Urknall-Ursel", "Blob", rgb(255, 255, 255), rgb(255, 200, 60), 2, 2 },
	{ "BigBangRobot", "Kaboom-Prime", "Robot", rgb(245, 245, 255), rgb(255, 120, 40), 3, 2 },
	{ "BigBangKing", "Schöpfer Bumm-Bumm", "King", rgb(255, 255, 255), rgb(255, 80, 40), 2, 0 },
})
add("Singularity", "Secret", {
	{ "SingularityGhost", "Schwarzloch-Schorsch", "Ghost", rgb(20, 20, 25), rgb(255, 255, 255), 2, 0 },
	{ "SingularitySpiky", "Punkt-Null-Pieks", "Spiky", rgb(10, 10, 15), rgb(180, 90, 255), 2, 0 },
	{ "SingularityCyclops", "Das Allsehende Nichts", "Cyclops", rgb(8, 8, 12), rgb(255, 40, 90), 1, 0 },
})
add("Multiverse", "Secret", {
	{ "MultiverseBug", "Portal-Käfer", "Bug", rgb(255, 60, 200), rgb(80, 255, 230), 4, 2 },
	{ "MultiverseCrystal", "Paralleli-Prisma", "Crystal", rgb(255, 80, 210), rgb(120, 200, 255), 3, 0 },
	{ "MultiverseSquid", "Multi-Krake Infinitus", "Squid", rgb(255, 50, 190), rgb(255, 255, 120), 3, 0 },
})
add("Omega", "Secret", {
	{ "OmegaRobot", "Omega-Wächter", "Robot", rgb(255, 0, 80), rgb(255, 220, 220), 2, 1 },
	{ "OmegaBlob", "Endboss-Schleim", "Blob", rgb(230, 0, 70), rgb(255, 230, 60), 3, 2 },
	{ "OmegaKing", "Omega-Imperator Rex", "King", rgb(255, 20, 90), rgb(40, 0, 20), 2, 0 },
})

-- MEHR AUSWAHL (Common .. Secret) -----------------------------------
add("Clay", "Common", {
	{ "ClayBlob", "Lehm-Lümmel", "Blob", rgb(190, 120, 90), rgb(255, 210, 160), 2, 1 },
	{ "ClayMushroom", "Ton-Töpfchen", "Mushroom", rgb(200, 130, 95), rgb(255, 235, 200), 2, 0 },
	{ "ClayKing", "Töpferkönig Tonius", "King", rgb(185, 115, 85), rgb(90, 160, 220), 2, 0 },
})
add("Coral", "Uncommon", {
	{ "CoralSquid", "Korallen-Kalle", "Squid", rgb(255, 120, 110), rgb(255, 220, 180), 2, 0 },
	{ "CoralBug", "Riff-Krabbler", "Bug", rgb(240, 100, 100), rgb(255, 200, 120), 4, 2 },
	{ "CoralCrystal", "Perlen-Prinzessin", "Crystal", rgb(255, 140, 130), rgb(255, 255, 255), 2, 0 },
})
add("Jade", "Rare", {
	{ "JadeRobot", "Jade-Bot J-7", "Robot", rgb(60, 190, 120), rgb(220, 255, 220), 2, 1 },
	{ "JadeGhost", "Grünschimmer-Geist", "Ghost", rgb(80, 200, 140), rgb(255, 240, 160), 2, 0 },
	{ "JadeKing", "Jadekaiser Jun", "King", rgb(50, 170, 110), rgb(255, 210, 80), 2, 0 },
})
add("Amethyst", "Rare", {
	{ "AmethystCrystal", "Amethyst-Andi", "Crystal", rgb(160, 90, 220), rgb(230, 200, 255), 2, 0 },
	{ "AmethystSpiky", "Drusen-Dorni", "Spiky", rgb(150, 80, 210), rgb(255, 220, 255), 2, 0 },
	{ "AmethystCyclops", "Violett-Visor", "Cyclops", rgb(170, 100, 230), rgb(255, 255, 255), 1, 2 },
})
add("Prism", "Epic", {
	{ "PrismCrystal", "Prisma-Pixi", "Crystal", rgb(180, 255, 250), rgb(255, 150, 255), 2, 0 },
	{ "PrismBlob", "Licht-Lolli", "Blob", rgb(170, 245, 240), rgb(255, 230, 120), 3, 2 },
	{ "PrismSquid", "Spektral-Spektakel", "Squid", rgb(190, 255, 250), rgb(120, 140, 255), 3, 0 },
})
add("Phoenix", "Legendary", {
	{ "PhoenixSpiky", "Flammen-Flitzer", "Spiky", rgb(255, 90, 40), rgb(255, 220, 60), 2, 0 },
	{ "PhoenixBug", "Glutflügel-Gina", "Bug", rgb(255, 110, 40), rgb(255, 240, 120), 4, 2 },
	{ "PhoenixKing", "Phönix-König Ignis", "King", rgb(255, 80, 30), rgb(255, 230, 80), 2, 0 },
})
add("Dragon", "Legendary", {
	{ "DragonBlob", "Schuppen-Schorschi", "Blob", rgb(40, 160, 90), rgb(255, 210, 60), 2, 2 },
	{ "DragonCyclops", "Drachenauge Draxx", "Cyclops", rgb(30, 140, 80), rgb(255, 120, 40), 1, 2 },
	{ "DragonKing", "Drachenfürst Smaragdus", "King", rgb(40, 170, 95), rgb(255, 200, 40), 2, 0 },
})
add("Vortex", "Mythic", {
	{ "VortexGhost", "Wirbel-Willi", "Ghost", rgb(90, 60, 255), rgb(140, 255, 255), 2, 0 },
	{ "VortexSquid", "Strudel-Krake", "Squid", rgb(80, 50, 240), rgb(255, 120, 255), 3, 0 },
	{ "VortexRobot", "Tornado-Tron 9000", "Robot", rgb(100, 70, 255), rgb(120, 255, 230), 3, 2 },
})
add("Starforge", "Celestial", {
	{ "StarforgeRobot", "Schmiede-Schorsch", "Robot", rgb(255, 180, 90), rgb(255, 90, 30), 2, 1 },
	{ "StarforgeSpiky", "Amboss-Igel", "Spiky", rgb(255, 170, 80), rgb(255, 250, 200), 2, 0 },
	{ "StarforgeKing", "Sternenschmied Vulkanus", "King", rgb(255, 190, 100), rgb(120, 60, 30), 2, 0 },
})
add("Constellation", "Celestial", {
	{ "ConstellationBug", "Sternbild-Käfer", "Bug", rgb(120, 150, 255), rgb(255, 255, 200), 4, 2 },
	{ "ConstellationGhost", "Großer-Wagen-Geist", "Ghost", rgb(130, 160, 255), rgb(255, 255, 255), 3, 0 },
	{ "ConstellationCrystal", "Orion der Funkelnde", "Crystal", rgb(110, 140, 255), rgb(255, 240, 140), 3, 0 },
})
add("Angelic", "Divine", {
	{ "AngelicBlob", "Federleicht-Flocke", "Blob", rgb(255, 250, 240), rgb(255, 215, 120), 2, 1 },
	{ "AngelicMushroom", "Wolken-Pilzi", "Mushroom", rgb(250, 245, 235), rgb(180, 220, 255), 2, 0 },
	{ "AngelicKing", "Seraphina die Strahlende", "King", rgb(255, 252, 245), rgb(255, 200, 90), 2, 0 },
})
add("Paradox", "Secret", {
	{ "ParadoxCyclops", "Zeitschleifen-Zyklop", "Cyclops", rgb(120, 255, 200), rgb(255, 80, 200), 1, 2 },
	{ "ParadoxRobot", "Widerspruch-Bot", "Robot", rgb(110, 240, 190), rgb(255, 255, 255), 3, 2 },
	{ "ParadoxSquid", "Paradox-Pulpo Primus", "Squid", rgb(130, 255, 210), rgb(90, 60, 255), 3, 0 },
})
add("Cipher", "Secret", {
	{ "CipherGhost", "Code-Geist 0101", "Ghost", rgb(40, 255, 120), rgb(10, 40, 20), 2, 0 },
	{ "CipherBug", "Bit-Käfer", "Bug", rgb(30, 230, 110), rgb(200, 255, 200), 4, 2 },
	{ "CipherKing", "Krypto-König Hex", "King", rgb(40, 255, 130), rgb(0, 60, 30), 2, 0 },
})

-- GODLY -------------------------------------------------------------
add("Olympus", "Godly", {
	{ "OlympusGhost", "Wolken-Zeusi", "Ghost", rgb(255, 220, 90), rgb(255, 255, 255), 2, 0 },
	{ "OlympusSpiky", "Blitzbart Bolt", "Spiky", rgb(255, 215, 80), rgb(120, 200, 255), 2, 0 },
	{ "OlympusKing", "Göttervater Olympio", "King", rgb(255, 225, 100), rgb(255, 255, 255), 2, 0 },
})
add("Valhalla", "Godly", {
	{ "ValhallaRobot", "Wikinger-Bot Wotan", "Robot", rgb(200, 220, 255), rgb(255, 200, 60), 2, 2 },
	{ "ValhallaBlob", "Met-Matsch", "Blob", rgb(210, 225, 255), rgb(255, 170, 60), 2, 2 },
	{ "ValhallaKing", "Schildkönig Odinus", "King", rgb(190, 215, 255), rgb(255, 210, 80), 1, 0 },
})
add("Zenith", "Godly", {
	{ "ZenithCrystal", "Gipfel-Glitzer", "Crystal", rgb(255, 200, 40), rgb(255, 255, 220), 2, 0 },
	{ "ZenithBug", "Kronen-Käfer", "Bug", rgb(255, 190, 30), rgb(255, 90, 60), 4, 2 },
	{ "ZenithKing", "Hoheit Zenithia", "King", rgb(255, 205, 50), rgb(150, 40, 200), 2, 0 },
})
add("Ambrosia", "Godly", {
	{ "AmbrosiaMushroom", "Nektar-Nuckel", "Mushroom", rgb(255, 150, 60), rgb(255, 240, 180), 2, 0 },
	{ "AmbrosiaSquid", "Honig-Krake Melis", "Squid", rgb(255, 160, 70), rgb(255, 230, 120), 3, 0 },
	{ "AmbrosiaCyclops", "Ambrosius das Allauge", "Cyclops", rgb(255, 140, 50), rgb(255, 255, 200), 1, 2 },
})

-- COSMIC ------------------------------------------------------------
add("Starseed", "Cosmic", {
	{ "StarseedBlob", "Sternenkeim-Kiki", "Blob", rgb(110, 90, 255), rgb(255, 255, 160), 2, 2 },
	{ "StarseedMushroom", "Galaxien-Pilz Gloria", "Mushroom", rgb(100, 80, 250), rgb(255, 200, 255), 2, 0 },
	{ "StarseedKing", "Saatkönig Stellaris", "King", rgb(120, 100, 255), rgb(255, 240, 120), 2, 0 },
})
add("Horizon", "Cosmic", {
	{ "HorizonGhost", "Horizont-Huschi", "Ghost", rgb(40, 20, 90), rgb(255, 140, 40), 2, 0 },
	{ "HorizonSpiky", "Schwerkraft-Stachel", "Spiky", rgb(35, 15, 80), rgb(200, 120, 255), 2, 0 },
	{ "HorizonCyclops", "Der Rand des Alls", "Cyclops", rgb(30, 10, 70), rgb(255, 200, 80), 1, 0 },
})
add("Astral", "Cosmic", {
	{ "AstralRobot", "Astral-Antrieb A1", "Robot", rgb(150, 200, 255), rgb(255, 255, 255), 3, 2 },
	{ "AstralCrystal", "Traumkristall Luma", "Crystal", rgb(160, 210, 255), rgb(255, 180, 255), 3, 0 },
	{ "AstralKing", "Astralkaiser Nebulon", "King", rgb(140, 190, 255), rgb(90, 40, 200), 2, 0 },
})

-- INFINITY ----------------------------------------------------------
add("Endless", "Infinity", {
	{ "EndlessSquid", "Endlos-Ennie", "Squid", rgb(0, 255, 180), rgb(255, 255, 255), 3, 0 },
	{ "EndlessBug", "Möbius-Käfer", "Bug", rgb(0, 240, 170), rgb(255, 120, 220), 4, 2 },
	{ "EndlessKing", "Unendlich-Kaiser Loop", "King", rgb(0, 255, 190), rgb(255, 230, 90), 2, 0 },
})
add("InfinityStone", "Infinity", {
	{ "InfinityStoneCrystal", "Ewigkeits-Edelstein", "Crystal", rgb(255, 230, 120), rgb(120, 255, 220), 2, 0 },
	{ "InfinityStoneGhost", "Achter-Geist Lemni", "Ghost", rgb(255, 235, 140), rgb(255, 90, 200), 2, 0 },
	{ "InfinityStoneKing", "Hüter der Steine", "King", rgb(255, 225, 110), rgb(80, 0, 160), 2, 0 },
})
add("Origin", "Infinity", {
	{ "OriginBlob", "Urfunke Ori", "Blob", rgb(255, 255, 255), rgb(0, 255, 200), 2, 2 },
	{ "OriginSpiky", "Anfangs-Stachel Alpha", "Spiky", rgb(250, 250, 255), rgb(255, 200, 60), 2, 0 },
	{ "OriginKing", "Origin, Schöpfer aller Eier", "King", rgb(255, 255, 255), rgb(0, 255, 180), 2, 0 },
})

-- NACHT-EIER (nur nachts in den Nestern, Blutmond-Ei nur im Blutmond) ---
add("Moonstone", "Rare", {
	{ "MoonstoneBlob", "Mondschein-Mops", "Blob", rgb(200, 210, 255), rgb(255, 255, 200), 2, 1 },
	{ "MoonstoneGhost", "Nachtgespenst Nuri", "Ghost", rgb(210, 220, 255), rgb(120, 140, 255), 2, 0 },
	{ "MoonstoneCrystal", "Mondkristall Selene", "Crystal", rgb(190, 205, 255), rgb(255, 255, 255), 2, 0 },
})
add("Shadow", "Epic", {
	{ "ShadowGhost", "Schattenhuscher", "Ghost", rgb(60, 40, 90), rgb(180, 120, 255), 2, 0 },
	{ "ShadowSpiky", "Dunkel-Dorn", "Spiky", rgb(50, 30, 80), rgb(255, 80, 200), 2, 0 },
	{ "ShadowCyclops", "Schattenauge Umbra", "Cyclops", rgb(40, 25, 70), rgb(140, 255, 200), 1, 2 },
})
add("Lunar", "Legendary", {
	{ "LunarMushroom", "Mondpilz Luno", "Mushroom", rgb(180, 200, 255), rgb(255, 250, 200), 2, 0 },
	{ "LunarRobot", "Mondlande-Bot", "Robot", rgb(170, 190, 250), rgb(255, 220, 90), 2, 1 },
	{ "LunarKing", "Mondkönigin Luna", "King", rgb(190, 205, 255), rgb(120, 100, 255), 2, 0 },
})
add("Starfall", "Mythic", {
	{ "StarfallBug", "Sternschnuppen-Glühwurm", "Bug", rgb(255, 240, 160), rgb(90, 120, 255), 4, 2 },
	{ "StarfallSquid", "Wunsch-Krake Wishy", "Squid", rgb(255, 235, 150), rgb(255, 150, 220), 3, 0 },
	{ "StarfallCrystal", "Sternregen-Stella", "Crystal", rgb(255, 245, 170), rgb(255, 255, 255), 3, 0 },
})
add("Eclipse", "Celestial", {
	{ "EclipseBlob", "Finsternis-Flubber", "Blob", rgb(30, 20, 50), rgb(255, 170, 40), 2, 2 },
	{ "EclipseGhost", "Korona-Geist", "Ghost", rgb(35, 25, 60), rgb(255, 220, 120), 2, 0 },
	{ "EclipseKing", "Eklipsus der Verdunkler", "King", rgb(25, 15, 45), rgb(255, 150, 30), 2, 0 },
})
add("BloodMoon", "Divine", {
	{ "BloodMoonSpiky", "Blutmond-Biest", "Spiky", rgb(200, 0, 30), rgb(255, 180, 180), 2, 0 },
	{ "BloodMoonGhost", "Purpur-Phantom", "Ghost", rgb(180, 0, 40), rgb(255, 90, 90), 2, 0 },
	{ "BloodMoonCyclops", "Blutmond-Auge Sanguis", "Cyclops", rgb(190, 0, 30), rgb(255, 230, 100), 1, 2 },
})

-- ADMIN (nur per Admin-Panel, spawnen nie von selbst) -------------------
add("AdminRainbow", "Admin", {
	{ "AdminRainbowBlob", "Regenbogen-Glibber-Gott", "Blob", rgb(255, 80, 80), rgb(255, 255, 255), 3, 2 },
	{ "AdminRainbowSquid", "Einhorn-Krake Unicorny", "Squid", rgb(255, 120, 220), rgb(120, 255, 255), 3, 1 },
	{ "AdminRainbowKing", "Regenbogen-Overlord", "King", rgb(255, 60, 60), rgb(255, 255, 255), 2, 0 },
}, { Rainbow = true })
add("AdminSun", "Admin", {
	{ "AdminSunSpiky", "Sonnen-Stachler Solaris", "Spiky", rgb(255, 200, 40), rgb(255, 90, 0), 2, 0 },
	{ "AdminSunCrystal", "Gold-Gottheit Glanz", "Crystal", rgb(255, 215, 60), rgb(255, 255, 220), 3, 0 },
	{ "AdminSunKing", "Sonnengott Helios Max", "King", rgb(255, 190, 0), rgb(255, 80, 0), 2, 0 },
}, { Fire = true })
add("AdminVoid", "Admin", {
	{ "AdminVoidGhost", "Void-Phantom", "Ghost", rgb(40, 0, 70), rgb(200, 60, 255), 3, 0 },
	{ "AdminVoidCyclops", "Abgrund-Auge", "Cyclops", rgb(25, 0, 45), rgb(255, 40, 200), 1, 2 },
	{ "AdminVoidKing", "Void-Imperator Nihil", "King", rgb(30, 0, 55), rgb(170, 0, 255), 2, 0 },
})
add("AdminChaos", "Admin", {
	{ "AdminChaosBug", "Chaos-Käfer Kawumm", "Bug", rgb(255, 40, 40), rgb(40, 255, 120), 4, 2 },
	{ "AdminChaosRobot", "Glitch-Bot ERR0R", "Robot", rgb(255, 50, 120), rgb(60, 255, 255), 3, 2 },
	{ "AdminChaosSpiky", "Kaos-Kaiser Kataklysmus", "Spiky", rgb(255, 30, 60), rgb(255, 255, 60), 3, 0 },
}, { Rainbow = true })

Aliens.Count = #Aliens.List

-- =====================================================================
--  Funktionen (Server und Client)
-- =====================================================================
local warned: { [string]: boolean } = {}

local function sanitizeLuck(luck: number?): number
	if type(luck) ~= "number" or luck ~= luck or luck < 1 then
		return 1
	end
	return math.min(luck, MAX_LUCK)
end

-- Gewicht einer Option mit Glück: Selten + Ultra werden mit dem Glück multipliziert
local function weightWithLuck(option: RollOption, luck: number): number
	local def = Aliens.ById[option.Id]
	local weight = math.max(0, option.Weight)
	if def and def.Tier ~= "Normal" then
		weight *= luck
	end
	return weight
end

-- Würfelt, welches Alien aus einem Meteor schlüpft. Gibt die Alien-Id zurück.
-- Unbekannter Meteor -> Warnung + erstes Alien der Liste (damit nie etwas kaputtgeht).
function Aliens.Roll(meteorId: string, luck: number?, rng: Random?): string
	local options = Aliens.ByMeteor[meteorId]
	if not options or #options == 0 then
		local key = tostring(meteorId)
		if not warned[key] then
			warned[key] = true
			warn("[Aliens] Keine Aliens für Meteor '" .. key .. "' – trage sie in Aliens.luau ein!")
		end
		return Aliens.List[1].Id
	end
	local l = sanitizeLuck(luck)
	local total = 0
	for _, option in ipairs(options) do
		total += weightWithLuck(option, l)
	end
	if total <= 0 then
		return options[1].Id
	end
	local roll = (rng or RNG):NextNumber() * total
	for _, option in ipairs(options) do
		roll -= weightWithLuck(option, l)
		if roll < 0 then
			return option.Id
		end
	end
	return options[#options].Id
end

-- Chancen (0..1) für die Anzeige, z.B. "Ultra 3%". Leere Liste bei unbekanntem Meteor.
function Aliens.GetChances(meteorId: string, luck: number?): { Chance }
	local result: { Chance } = {}
	local options = Aliens.ByMeteor[meteorId]
	if not options then
		return result
	end
	local l = sanitizeLuck(luck)
	local total = 0
	for _, option in ipairs(options) do
		total += weightWithLuck(option, l)
	end
	for _, option in ipairs(options) do
		local def = Aliens.ById[option.Id]
		table.insert(result, {
			Id = option.Id,
			Name = def and def.Name or option.Id,
			Tier = def and def.Tier or "Normal",
			Chance = total > 0 and weightWithLuck(option, l) / total or 0,
		})
	end
	return result
end

-- Alle 3 Alien-Definitionen eines Meteors (Normal, Selten, Ultra)
function Aliens.ForMeteor(meteorId: string): { AlienDef }
	local result: { AlienDef } = {}
	for _, option in ipairs(Aliens.ByMeteor[meteorId] or {}) do
		local def = Aliens.ById[option.Id]
		if def then
			table.insert(result, def)
		end
	end
	return result
end

return Aliens
