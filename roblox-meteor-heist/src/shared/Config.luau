-- =====================================================================
--  METEOR HEIST – ZENTRALE EINSTELLUNGEN
--  Hier stellst du (fast) alles ein, ohne anderen Code anzufassen.
-- =====================================================================

-- Aliens.luau enthält alle Aliens (darf Config NICHT laden – nur Config lädt Aliens)
local Aliens = require(script.Parent:WaitForChild("Aliens"))

local Config = {}

Config.GameName = "Meteor Heist"

-- ---------------------------------------------------------------------
-- 1) ADMINS – wer das Admin-Panel sehen und benutzen darf.
--    NUR DU: Wem das Spiel gehört (dein Account, mit dem du es
--    veröffentlichst), ist Admin. Du musst hier nichts eintragen!
--    Admin kann man NICHT kaufen – der Server prüft es bei jeder Aktion.
-- ---------------------------------------------------------------------
Config.OwnerIsAdmin = true

-- Weitere Admins: LEER LASSEN, dann bist nur du Admin.
Config.AdminUserIds = {}

-- Beim Testen in Roblox Studio bist du Admin (zum Ausprobieren).
-- Im veröffentlichten Spiel zählt nur der Besitzer (siehe oben).
Config.StudioIsAdmin = true

-- ---------------------------------------------------------------------
-- 2) MONETARISIERUNG – IDs aus dem Creator Dashboard eintragen.
--    0 = noch nicht eingerichtet (Button im Shop ist dann ausgegraut).
-- ---------------------------------------------------------------------
Config.GamePasses = {
	{
		Key = "DoubleCash",
		Id = 0,
		Name = "2x Cash",
		Description = "Verdopple dein Einkommen für immer!",
		Icon = "💰",
	},
	{ Key = "VIP", Id = 0, Name = "VIP", Description = "+25% Cash, 90s Lock, VIP-Tag", Icon = "👑" },
	{
		Key = "ExtraSlots",
		Id = 0,
		Name = "+6 Plätze",
		Description = "18 statt 12 Plätze in deiner Base",
		Icon = "☄️",
	},
	{
		Key = "AutoCollect",
		Id = 0,
		Name = "Auto Collect",
		Description = "Geld wird automatisch eingesammelt",
		Icon = "🤖",
	},
	{
		Key = "FastCharge",
		Id = 0,
		Name = "⚡ 2x Schlüpfen & Wachsen",
		Description = "Meteore schlüpfen und Aliens leveln doppelt so schnell",
		Icon = "⚡",
	},
	{
		Key = "SpeedBoots",
		Id = 0,
		Name = "👟 2x Schritte",
		Description = "Doppelt so viele Schritte auf jedem Laufband",
		Icon = "👟",
	},
}

-- Developer Products (beliebig oft kaufbar).
-- Type "Cash": Spieler bekommt "Minutes" Minuten seines Einkommens, mindestens "Min".
-- Type "Steps": so viele Schritte, wie man in "Minutes" Minuten auf dem besten
--               freigeschalteten Laufband laufen würde, mindestens "Min".
Config.Products = {
	{ Key = "CashSmall", Id = 0, Name = "Cash Paket S", Icon = "💵", Type = "Cash", Minutes = 10, Min = 2500 },
	{ Key = "CashMedium", Id = 0, Name = "Cash Paket M", Icon = "💰", Type = "Cash", Minutes = 60, Min = 20000 },
	{ Key = "CashLarge", Id = 0, Name = "Cash Paket XL", Icon = "🏦", Type = "Cash", Minutes = 360, Min = 150000 },
	{
		Key = "ServerLuck",
		Id = 0,
		Name = "2x Glück für den Server (15 Min)",
		Icon = "🍀",
		Type = "ServerLuck",
		Mult = 2,
		Minutes = 15,
	},
	{ Key = "Speed10", Id = 0, Name = "👟 Schritte-Paket", Icon = "👟", Type = "Steps", Minutes = 10, Min = 1000 },
	{ Key = "MeteorShower", Id = 0, Name = "Meteoritenschauer JETZT", Icon = "🌠", Type = "Shower" },
	{
		Key = "LegendaryMeteor",
		Id = 0,
		Name = "Zufälliger Legendary Meteor",
		Icon = "🌟",
		Type = "Meteor",
		Rarity = "Legendary",
	},
	{
		Key = "MythicMeteor",
		Id = 0,
		Name = "Zufälliger Mythic Meteor",
		Icon = "🔮",
		Type = "Meteor",
		Rarity = "Mythic",
	},
}

-- ---------------------------------------------------------------------
-- 3) SPIEL-BALANCE
-- ---------------------------------------------------------------------
Config.StartCash = 100
Config.BaseSlots = 12
Config.ExtraSlotsAmount = 6 -- Gamepass "+6 Plätze" (max. 18 – die Map baut 18 Slot-Pads je Base)
Config.MaxPlots = 8 -- Spieler pro Server (in den Game Settings "Max Players" = 8 setzen!)
Config.SellRatio = 0.5 -- Verkauf = 50% vom Wert

Config.LockDuration = 60 -- Sekunden Base-Sperre
Config.LockDurationVIP = 90

Config.GrabHoldDuration = 0.25 -- E halten zum Kaufen/Schnappen
Config.StealHoldDuration = 1.5 -- E halten zum Klauen
Config.CarryTimeout = 60 -- Sekunden Zeit, um die Beute in die eigene Base zu bringen
Config.NormalWalkSpeed = 16
Config.CarrySpeedFactor = 0.65 -- beim Tragen: 65% vom eigenen Tempo

-- SPEED FARM: Auf den Laufbändern (Treadmills) am Spawn-Platz laufen = Schritte 👟 sammeln.
-- Mehr Schritte = schneller laufen. Höhere Laufbänder geben viel mehr Schritte,
-- brauchen aber erst genug Schritte zum Freischalten.
--   Required = so viele Schritte braucht man für dieses Laufband
--   Rate     = Schritte pro Tick (alle TreadmillTick Sekunden)
Config.Treadmills = {
	{ Id = "Holz", Name = "Holz-Laufband", Required = 0, Rate = 1, Color = Color3.fromRGB(170, 115, 60) },
	{ Id = "Stein", Name = "Stein-Laufband", Required = 500, Rate = 6, Color = Color3.fromRGB(150, 150, 160) },
	{ Id = "Eisen", Name = "Eisen-Laufband", Required = 15000, Rate = 40, Color = Color3.fromRGB(200, 210, 225) },
	{ Id = "Gold", Name = "Gold-Laufband", Required = 400000, Rate = 300, Color = Color3.fromRGB(255, 200, 40) },
	{
		Id = "Diamant",
		Name = "Diamant-Laufband",
		Required = 1e7,
		Rate = 2500,
		Color = Color3.fromRGB(90, 225, 255),
	},
	{
		Id = "Galaxie",
		Name = "Galaxie-Laufband",
		Required = 3e8,
		Rate = 20000,
		Color = Color3.fromRGB(150, 80, 255),
	},
	{
		Id = "Regenbogen",
		Name = "Regenbogen-Laufband",
		Required = 1e10,
		Rate = 180000,
		Color = Color3.fromRGB(255, 80, 200),
		Rainbow = true,
	},
}
Config.TreadmillTick = 0.5 -- alle 0,5 Sekunden gibt es Schritte
Config.MaxWalkSpeed = 80 -- schneller geht es nicht (16 normal + max. 64 durch Schritte)
Config.StepsPerRebirth = 0.25 -- jeder Rebirth: +25% Schritte auf allen Laufbändern

Config.BonkCooldown = 0.8
Config.BonkRange = 9
Config.BonkForce = 70

-- SCHLÜPFEN: Gekaufte Meteore brauchen Zeit (HatchTime bei den Seltenheiten unten),
-- dann schlüpft ein ALIEN. Erst das Alien verdient Geld!
-- AUFLADEN: Aliens in deiner Base wachsen (Level 1 -> MaxLevel).
-- Zeit bis zum nächsten Level = ChargeSecondsPerLevel * aktuelles Level
Config.MaxLevel = 20
Config.ChargeSecondsPerLevel = 60 -- Level 1->20 dauert ca. 3 Stunden Spielzeit
Config.IncomePerLevel = 0.1 -- +10% Einkommen pro Level

-- INDEX: jedes neu entdeckte Alien gibt dauerhaft +1% Einkommen
Config.IndexBonusPerAlien = 0.01

-- LAUFBAND (Förderband) in der Map-Mitte: Meteore fahren vorbei, E = kaufen
Config.BeltSpawnInterval = 1.0 -- alle X Sekunden kommt ein neuer Meteor aufs Band
Config.BeltSpeed = 9 -- Studs pro Sekunde
Config.MaxBeltMeteors = 160 -- Sicherheitsgrenze (mehr liegen nie gleichzeitig auf dem Band)

-- GRATIS-ZONE am Spawn-Platz: hier landen Gratis- und Admin-Meteore
Config.FreeMeteorLifetime = 180 -- Sekunden, bis ein Gratis-Meteor verschwindet
Config.MaxFreeMeteors = 20

-- METEORITENSCHAUER-EVENT: alle X Sekunden, Y Sekunden lang, mehr + bessere Meteore
Config.ShowerInterval = 480
Config.ShowerDuration = 60
Config.ShowerBeltInterval = 0.35 -- im Schauer kommen die Meteore viel schneller
Config.ShowerLuck = 3

Config.OfflineIncomeRate = 0.25 -- 25% Einkommen während man offline ist
Config.OfflineMaxSeconds = 3 * 3600

-- REBIRTH: Cash + Meteore/Aliens weg, dafür +50% Einkommen für immer
-- und höhere Seltenheiten kaufbar. Schritte und Index bleiben erhalten.
Config.RebirthBaseCost = 50000000 -- Kosten = Basis * RebirthCostGrowth ^ Rebirths
Config.RebirthCostGrowth = 3
Config.RebirthMultPerLevel = 0.5

Config.DailyRewardMinCash = 500
Config.DailyRewardIncomeSeconds = 120 -- Tagesbonus = 2 Min Einkommen x Streak (max 7)

Config.PremiumBonus = 0.1 -- +10% für Roblox Premium (bringt dir mehr Premium-Payouts)
Config.VIPBonus = 0.25

-- ---------------------------------------------------------------------
-- 4) SELTENHEITEN – Weight = Spawnchance (relativ), Size = Größe des Meteors
--    Kleine kommen oft, große & seltene kaum -> "erst kleine, dann immer bessere"
--    HatchTime = Sekunden bis das Alien schlüpft
--    RequiredRebirths = so viele Rebirths braucht man, um diese Seltenheit zu KAUFEN
--    (klauen geht immer!)
--    "Admin" = nur vom Admin spawnbar (Weight 0 -> kommt nie von selbst)
-- ---------------------------------------------------------------------
Config.Rarities = {
	{ Name = "Common", Weight = 50, Size = 2, Color = Color3.fromRGB(200, 200, 200), HatchTime = 8 },
	{ Name = "Uncommon", Weight = 26, Size = 2.5, Color = Color3.fromRGB(85, 220, 95), HatchTime = 15 },
	{ Name = "Rare", Weight = 13, Size = 3, Color = Color3.fromRGB(70, 150, 255), HatchTime = 30 },
	{ Name = "Epic", Weight = 6.5, Size = 3.6, Color = Color3.fromRGB(180, 80, 255), HatchTime = 50 },
	{ Name = "Legendary", Weight = 3, Size = 4.2, Color = Color3.fromRGB(255, 190, 40), HatchTime = 80 },
	{ Name = "Mythic", Weight = 1.1, Size = 4.9, Color = Color3.fromRGB(255, 60, 90), HatchTime = 120 },
	{
		Name = "Celestial",
		Weight = 0.3,
		Size = 5.6,
		Color = Color3.fromRGB(90, 230, 255),
		HatchTime = 180,
		RequiredRebirths = 1,
	},
	{
		Name = "Divine",
		Weight = 0.08,
		Size = 6.4,
		Color = Color3.fromRGB(255, 240, 150),
		HatchTime = 260,
		RequiredRebirths = 3,
	},
	{
		Name = "Secret",
		Weight = 0.02,
		Size = 7.2,
		Color = Color3.fromRGB(255, 255, 255),
		HatchTime = 360,
		RequiredRebirths = 5,
	},
	{ Name = "Admin", Weight = 0, Size = 8, Color = Color3.fromRGB(255, 40, 40), HatchTime = 5, AdminOnly = true },
}

-- Mutationen multiplizieren Wert UND Einkommen
Config.Mutations = {
	{ Name = "Normal", Weight = 88, Mult = 1 },
	{ Name = "Gold", Weight = 10, Mult = 2, Color = Color3.fromRGB(255, 205, 50) },
	{ Name = "Diamond", Weight = 1.8, Mult = 4, Color = Color3.fromRGB(120, 230, 255) },
	{ Name = "Cosmic", Weight = 0.2, Mult = 10, Color = Color3.fromRGB(150, 70, 255) },
}

-- ---------------------------------------------------------------------
-- 5) METEORE – einfach Zeilen hinzufügen (Id muss einmalig sein!)
--    Spawnable = false -> kommt nicht von selbst aufs Laufband (nur Admin-Panel / Produkte)
--    Für JEDEN Meteor müssen in Aliens.luau 3 Aliens stehen!
--    Effects (optional): Rainbow = Regenbogen-Farben, Aura = Partikel, Highlight = Umriss,
--    BigLight = starkes Licht
-- ---------------------------------------------------------------------
Config.Meteors = {
	{
		Id = "Pebble",
		Name = "Pebble Rock",
		Rarity = "Common",
		Price = 25,
		Income = 1,
		Color = Color3.fromRGB(130, 125, 120),
	},
	{
		Id = "Dusty",
		Name = "Dusty Chunk",
		Rarity = "Common",
		Price = 64,
		Income = 2,
		Color = Color3.fromRGB(150, 120, 90),
	},
	{
		Id = "Ember",
		Name = "Ember Stone",
		Rarity = "Common",
		Price = 160,
		Income = 5,
		Color = Color3.fromRGB(200, 90, 50),
	},
	{
		Id = "Comet",
		Name = "Ice Comet",
		Rarity = "Uncommon",
		Price = 410,
		Income = 12,
		Color = Color3.fromRGB(170, 230, 255),
	},
	{
		Id = "Sulfur",
		Name = "Sulfur Shard",
		Rarity = "Uncommon",
		Price = 1100,
		Income = 30,
		Color = Color3.fromRGB(230, 220, 70),
	},
	{
		Id = "Moss",
		Name = "Moss Rock",
		Rarity = "Uncommon",
		Price = 2700,
		Income = 66,
		Color = Color3.fromRGB(80, 140, 60),
	},
	{
		Id = "Cobalt",
		Name = "Cobalt Core",
		Rarity = "Rare",
		Price = 6900,
		Income = 150,
		Color = Color3.fromRGB(40, 80, 200),
	},
	{
		Id = "Magma",
		Name = "Magma Heart",
		Rarity = "Rare",
		Price = 18000,
		Income = 360,
		Color = Color3.fromRGB(255, 80, 20),
	},
	{
		Id = "Quartz",
		Name = "Rose Quartz",
		Rarity = "Rare",
		Price = 45000,
		Income = 810,
		Color = Color3.fromRGB(255, 150, 190),
	},
	{
		Id = "Starlight",
		Name = "Starlight Shard",
		Rarity = "Epic",
		Price = 110000,
		Income = 1800,
		Color = Color3.fromRGB(255, 250, 200),
	},
	{
		Id = "Plasma",
		Name = "Plasma Orb",
		Rarity = "Epic",
		Price = 290000,
		Income = 4300,
		Color = Color3.fromRGB(200, 80, 255),
	},
	{
		Id = "Thunder",
		Name = "Thunder Rock",
		Rarity = "Epic",
		Price = 740000,
		Income = 9900,
		Color = Color3.fromRGB(255, 235, 60),
	},
	{
		Id = "Solar",
		Name = "Solar Flare",
		Rarity = "Legendary",
		Price = 1900000,
		Income = 23000,
		Color = Color3.fromRGB(255, 170, 0),
	},
	{
		Id = "Aurora",
		Name = "Aurora Crystal",
		Rarity = "Legendary",
		Price = 4800000,
		Income = 52000,
		Color = Color3.fromRGB(80, 255, 180),
	},
	{
		Id = "Titan",
		Name = "Titan Boulder",
		Rarity = "Legendary",
		Price = 12000000,
		Income = 120000,
		Color = Color3.fromRGB(110, 90, 80),
	},
	{
		Id = "Nebula",
		Name = "Nebula Heart",
		Rarity = "Mythic",
		Price = 31000000,
		Income = 280000,
		Color = Color3.fromRGB(120, 50, 200),
	},
	{
		Id = "BlackHole",
		Name = "Black Hole Fragment",
		Rarity = "Mythic",
		Price = 80000000,
		Income = 650000,
		Color = Color3.fromRGB(15, 0, 30),
	},
	{
		Id = "Pulsar",
		Name = "Pulsar Gem",
		Rarity = "Mythic",
		Price = 200000000,
		Income = 1500000,
		Color = Color3.fromRGB(0, 220, 255),
	},
	{
		Id = "Supernova",
		Name = "Supernova Shard",
		Rarity = "Celestial",
		Price = 520000000,
		Income = 3400000,
		Color = Color3.fromRGB(255, 120, 40),
	},
	{
		Id = "Quasar",
		Name = "Quasar Core",
		Rarity = "Celestial",
		Price = 1300000000,
		Income = 7800000,
		Color = Color3.fromRGB(255, 255, 140),
	},
	{
		Id = "Galaxy",
		Name = "Galaxy Spiral",
		Rarity = "Celestial",
		Price = 3400000000,
		Income = 18000000,
		Color = Color3.fromRGB(150, 90, 255),
	},
	{
		Id = "Halo",
		Name = "Halo Stone",
		Rarity = "Divine",
		Price = 8600000000,
		Income = 42000000,
		Color = Color3.fromRGB(255, 245, 210),
	},
	{
		Id = "Seraph",
		Name = "Seraph Crystal",
		Rarity = "Divine",
		Price = 22000000000,
		Income = 98000000,
		Color = Color3.fromRGB(255, 220, 120),
	},
	{
		Id = "Eternity",
		Name = "Eternity Orb",
		Rarity = "Divine",
		Price = 56000000000,
		Income = 230000000,
		Color = Color3.fromRGB(200, 255, 255),
	},
	{
		Id = "BigBang",
		Name = "Big Bang Core",
		Rarity = "Secret",
		Price = 140000000000,
		Income = 510000000,
		Color = Color3.fromRGB(255, 255, 255),
	},
	{
		Id = "Singularity",
		Name = "Singularity",
		Rarity = "Secret",
		Price = 360000000000,
		Income = 1200000000,
		Color = Color3.fromRGB(5, 5, 5),
	},
	{
		Id = "Multiverse",
		Name = "Multiverse Key",
		Rarity = "Secret",
		Price = 930000000000,
		Income = 2800000000,
		Color = Color3.fromRGB(255, 60, 200),
	},
	{
		Id = "Omega",
		Name = "Omega Core",
		Rarity = "Secret",
		Price = 5000000000000,
		Income = 15000000000,
		Color = Color3.fromRGB(255, 0, 80),
		Spawnable = false,
	},

	-- 👑 ADMIN-METEORE: nur der Admin kann sie spawnen (Admin-Panel)
	{
		Id = "AdminRainbow",
		Name = "Rainbow Overlord",
		Rarity = "Admin",
		Price = 10000000000000,
		Income = 30000000000,
		Color = Color3.fromRGB(255, 90, 220),
		Spawnable = false,
		Effects = { Rainbow = true, Aura = true, Highlight = true, BigLight = true },
	},
	{
		Id = "AdminSun",
		Name = "Godly Sun",
		Rarity = "Admin",
		Price = 60000000000000,
		Income = 150000000000,
		Color = Color3.fromRGB(255, 200, 30),
		Spawnable = false,
		Effects = { Rainbow = false, Aura = true, Highlight = true, BigLight = true },
	},
	{
		Id = "AdminVoid",
		Name = "Void Emperor",
		Rarity = "Admin",
		Price = 250000000000000,
		Income = 600000000000,
		Color = Color3.fromRGB(70, 0, 120),
		Spawnable = false,
		Effects = { Rainbow = false, Aura = true, Highlight = true, BigLight = true },
	},
	{
		Id = "AdminChaos",
		Name = "Chaos Core",
		Rarity = "Admin",
		Price = 1000000000000000,
		Income = 2000000000000,
		Color = Color3.fromRGB(255, 30, 60),
		Spawnable = false,
		Effects = { Rainbow = true, Aura = true, Highlight = true, BigLight = true },
	},
}

-- ---------------------------------------------------------------------
-- 6) TECHNIK (nur ändern, wenn du weißt was du tust)
--    ACHTUNG: DataStoreName ändern = alle Spielstände sind weg!
-- ---------------------------------------------------------------------
Config.DataStoreName = "MeteorHeist_PlayerData_v1"
Config.LeaderboardStoreName = "MeteorHeist_TopEarned_v1"
Config.MessagingTopic = "MeteorHeist_Admin_v1"
Config.AutoSaveInterval = 90

-- =====================================================================
-- Ab hier: automatisch erzeugte Nachschlage-Tabellen (nicht ändern)
-- =====================================================================
Config.MeteorsById = {}
Config.RaritiesByName = {}
Config.RarityIndex = {}
Config.MutationsByName = {}
Config.GamePassesByKey = {}
Config.ProductsById = {}
Config.ProductsByKey = {}
Config.MeteorsByRarity = {} -- nur Meteore, die von selbst aufs Laufband kommen
Config.MeteorsByRarityAll = {} -- alle Meteore (auch Admin / nicht spawnbare)
Config.AdminMeteors = {} -- alle Meteore mit Rarity "Admin"
Config.TreadmillsById = {}

for i, rarity in ipairs(Config.Rarities) do
	Config.RaritiesByName[rarity.Name] = rarity
	Config.RarityIndex[rarity.Name] = i
	Config.MeteorsByRarity[rarity.Name] = {}
	Config.MeteorsByRarityAll[rarity.Name] = {}
end
for _, meteor in ipairs(Config.Meteors) do
	assert(Config.MeteorsById[meteor.Id] == nil, "Doppelte Meteor-Id: " .. meteor.Id)
	local rarity = Config.RaritiesByName[meteor.Rarity]
	assert(rarity, "Unbekannte Rarity bei " .. meteor.Id)
	Config.MeteorsById[meteor.Id] = meteor
	table.insert(Config.MeteorsByRarityAll[meteor.Rarity], meteor)
	if meteor.Spawnable ~= false and not rarity.AdminOnly then
		table.insert(Config.MeteorsByRarity[meteor.Rarity], meteor)
	end
	if rarity.AdminOnly then
		table.insert(Config.AdminMeteors, meteor)
	end
	if not Aliens.ByMeteor[meteor.Id] then
		warn("[Config] Für Meteor '" .. meteor.Id .. "' fehlen die Aliens in Aliens.luau!")
	end
end
for _, mutation in ipairs(Config.Mutations) do
	Config.MutationsByName[mutation.Name] = mutation
end
for _, pass in ipairs(Config.GamePasses) do
	Config.GamePassesByKey[pass.Key] = pass
end
for _, product in ipairs(Config.Products) do
	Config.ProductsByKey[product.Key] = product
	if product.Id ~= 0 then
		assert(Config.ProductsById[product.Id] == nil, "Doppelte Product-Id: " .. product.Id)
		Config.ProductsById[product.Id] = product
	end
end
for i, treadmill in ipairs(Config.Treadmills) do
	assert(Config.TreadmillsById[treadmill.Id] == nil, "Doppelte Laufband-Id: " .. treadmill.Id)
	if i > 1 then
		assert(treadmill.Required >= Config.Treadmills[i - 1].Required, "Laufbänder aufsteigend sortieren!")
	end
	Config.TreadmillsById[treadmill.Id] = treadmill
end

-- Hilfsfunktionen, die Server und Client gleich rechnen
function Config.LevelMult(level: number): number
	return 1 + Config.IncomePerLevel * (math.max(1, level) - 1)
end

-- Das geschlüpfte Alien eines Eintrags (nil = noch nicht geschlüpft / unbekannt)
function Config.GetAlien(entry)
	if not entry or entry.Alien == nil then
		return nil
	end
	return Aliens.ById[entry.Alien]
end

-- Anzeigename: Alien-Name wenn geschlüpft, sonst Meteor-Name
function Config.EntryName(entry): string
	local alien = Config.GetAlien(entry)
	if alien then
		return alien.Name
	end
	local def = entry and Config.MeteorsById[entry.Id]
	return def and def.Name or "???"
end

-- Sekunden bis zum Schlüpfen für einen Meteor-Typ
function Config.HatchTime(meteorId: string): number
	local def = Config.MeteorsById[meteorId]
	local rarity = def and Config.RaritiesByName[def.Rarity]
	return rarity and rarity.HatchTime or 10
end

-- Einkommen pro Sekunde: nur geschlüpfte Aliens verdienen Geld!
function Config.MeteorIncome(entry): number
	if not entry or entry.Alien == nil then
		return 0
	end
	local def = Config.MeteorsById[entry.Id]
	if not def then
		return 0
	end
	local alien = Aliens.ById[entry.Alien]
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]
	local alienMult = alien and alien.IncomeMult or 1
	return def.Income * alienMult * mut.Mult * Config.LevelMult(entry.Lv or 1)
end

-- Wert (Kaufpreis am Laufband, Verkaufswert = Wert * SellRatio)
function Config.MeteorValue(entry): number
	local def = entry and Config.MeteorsById[entry.Id]
	if not def then
		return 0
	end
	local alien = entry.Alien ~= nil and Aliens.ById[entry.Alien] or nil
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]
	local alienMult = alien and alien.IncomeMult or 1
	return def.Price * alienMult * mut.Mult * Config.LevelMult(entry.Lv or 1)
end

function Config.ChargeTime(level: number): number
	return Config.ChargeSecondsPerLevel * level
end

-- Laufgeschwindigkeit aus den Schritten (logarithmisch, max. MaxWalkSpeed)
function Config.StepsSpeed(steps: number): number
	steps = tonumber(steps) or 0
	if steps ~= steps or steps < 0 then
		steps = 0
	end
	return 16 + math.min(64, math.floor(math.log10(1 + steps) * 6))
end

-- Bestes freigeschaltetes Laufband (Holz ist immer frei)
function Config.BestTreadmill(steps: number)
	local best = Config.Treadmills[1]
	for _, treadmill in ipairs(Config.Treadmills) do
		if steps >= treadmill.Required then
			best = treadmill
		end
	end
	return best
end

function Config.RebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

return Config
