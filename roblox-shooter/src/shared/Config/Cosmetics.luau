-- =====================================================================
--  CLUTCH CLASH – KOSMETIK-KATALOG (Shared/Config/Cosmetics)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B19 + C15.
--  Alles ist Part-/UI-basiert (keine hochgeladenen Assets):
--    Wraps     = Farben/Material pro Rollen-Gruppe (Body/Detail/Accent/Metal/Grip – die orange
--                Spitze "Tip" wird NIE verändert), optional Anim ("Pulse"/"Rainbow"/"Galaxy"/"Sparkle")
--    Skins     = alternatives Waffen-Rezept (Rezept liegt in Shared/WeaponModels unter der Skin-Id)
--    Charms    = Mini-Modell (Rezept in Shared/CosmeticModels unter der Charm-Id)
--    Finisher  = Client-Effekt (Builder in Client/Modules/Finishers unter der Finisher-Id)
--    Tracer    = Beam-Farbe/-Breite
--    Titel     = Text unter dem Namen ("TT_…")
--
--  Preise:  Price = { Coins = n }  -> mit Münzen kaufbar (Basis-Wraps)
--           Price = nil            -> Katalog-Listenpreis in Gems nach Rarity (Config.Shop.CatalogPrices)
--  Quelle (Source):
--    "Catalog"  Katalog (+ evtl. Kiste)          "Coins"   Münz-Wrap (+ Kiste -> auch für Gems)
--    "Pass"     Clutch Pass (exklusiv während seiner Saison, siehe Exclusive), danach Katalog
--    "VIP"      gehört automatisch jedem mit VIP-Pass      "Starter" nur im Starter-Paket
--    "Mastery"  Meisterschafts-Stufe der Waffe (nie kaufbar, kein Besitz-Eintrag)
--    "Login"    Login-Kalender    "Default" gehört allen    "Earned" erspielt (Level, Erfolge …)
--
--  Öffentliche API (zusätzlich zu den Daten):
--    Cosmetics.ById[id] -> def (mit def.Id und def.Kind)      Cosmetics.Get(id): def?
--    Cosmetics.IsExclusive(id, seasonId): boolean               Pass-Item noch in seiner Saison?
--    Cosmetics.Validate(Config): { string }
-- =====================================================================

local rgb = Color3.fromRGB

local Cosmetics = {}

Cosmetics.Rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
Cosmetics.RarityRank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
Cosmetics.Kinds = { "Wrap", "Skin", "Charm", "Finisher", "Tracer", "Title" }
Cosmetics.Defaults = { Finisher = "F_Confetti", Tracer = "T_Team" }
Cosmetics.WrapRoles = { "Body", "Detail", "Accent", "Metal", "Grip" } -- "Tip" bleibt immer orange
Cosmetics.Anims = { Pulse = true, Rainbow = true, Galaxy = true, Sparkle = true }
Cosmetics.AnimHz = 10 -- Wrap-Animationen: 10 Hz
Cosmetics.AnimRange = 80 -- nur bis 80 Studs zur Kamera
-- Erlaubte Materialien (Muss-Regel 11: NIE "Ice")
Cosmetics.Materials = {
	SmoothPlastic = true,
	Plastic = true,
	Neon = true,
	Foil = true,
	Glass = true,
	Metal = true,
	DiamondPlate = true,
	Fabric = true,
	Wood = true,
	WoodPlanks = true,
	Marble = true,
	Granite = true,
	Slate = true,
	Concrete = true,
	ForceField = true,
	Pebble = true,
	CorrodedMetal = true,
}

-- 15 Waffen (für Meisterschafts-Titel und Skin-Prüfung; Namen wie B11)
local WEAPONS = {
	{ Key = "PopRifle", de = "Pop-Gewehr", en = "Pop Rifle" },
	{ Key = "BuzzSMG", de = "Summ-MP", en = "Buzz SMG" },
	{ Key = "BurstBlaster", de = "Salven-Blaster", en = "Burst Blaster" },
	{ Key = "Scatter", de = "Streuer", en = "Scatter" },
	{ Key = "Longshot", de = "Fernschuss", en = "Longshot" },
	{ Key = "PopRocket", de = "Plopp-Rakete", en = "Pop Rocket" },
	{ Key = "PipPistol", de = "Pieps-Pistole", en = "Pip Pistol" },
	{ Key = "HandCannon", de = "Hand-Kanone", en = "Hand Cannon" },
	{ Key = "MiniScatter", de = "Mini-Streuer", en = "Mini Scatter" },
	{ Key = "BoxingGloves", de = "Boxhandschuhe", en = "Boxing Gloves" },
	{ Key = "BonkHammer", de = "Bonk-Hammer", en = "Bonk Hammer" },
	{ Key = "LaserSword", de = "Laserschwert", en = "Laser Sword" },
	{ Key = "PopGrenade", de = "Plopp-Granate", en = "Pop Grenade" },
	{ Key = "SmokeBomb", de = "Rauchbombe", en = "Smoke Bomb" },
	{ Key = "MedFizz", de = "Heil-Limo", en = "Med Fizz" },
}
Cosmetics.WeaponKeys = {}
for _, w in ipairs(WEAPONS) do
	table.insert(Cosmetics.WeaponKeys, w.Key)
end

-- ---------------------------------------------------------------------
-- 1) WRAPS (34) – Farben pro Rolle, Material als Text (Enum.Material.<Name>)
-- ---------------------------------------------------------------------
type RoleMats = { Body: string?, Detail: string?, Accent: string?, Metal: string?, Grip: string? }

local function roles(body: Color3, detail: Color3, accent: Color3, metal: Color3, grip: Color3, mats: RoleMats?)
	local m: RoleMats = mats or {}
	return {
		Body = { Color = body, Material = m.Body or "SmoothPlastic" },
		Detail = { Color = detail, Material = m.Detail or "SmoothPlastic" },
		Accent = { Color = accent, Material = m.Accent or "Neon" },
		Metal = { Color = metal, Material = m.Metal or "Foil" },
		Grip = { Color = grip, Material = m.Grip or "SmoothPlastic" },
	}
end

local CREAM = rgb(244, 235, 221)
local CHARCOAL = rgb(43, 43, 51)
local SILVER = rgb(200, 205, 215)
local GOLD = rgb(255, 200, 40)
local WHITE = rgb(240, 242, 248)

Cosmetics.Wraps = {
	-- Basis-Wraps für Münzen (B18.3: 6 Stück, 1.500–3.000) – zusätzlich in der Kiste
	W_Mint = {
		Name = { de = "Minze", en = "Mint" },
		Rarity = "Common",
		Roles = roles(rgb(154, 209, 212), CREAM, rgb(90, 230, 200), SILVER, CHARCOAL),
		Price = { Coins = 1500 },
		Source = "Coins",
	},
	W_Sky = {
		Name = { de = "Himmel", en = "Sky" },
		Rarity = "Common",
		Roles = roles(rgb(120, 190, 255), WHITE, rgb(60, 170, 255), SILVER, rgb(28, 32, 64)),
		Price = { Coins = 1500 },
		Source = "Coins",
	},
	W_Sunny = {
		Name = { de = "Sonnig", en = "Sunny" },
		Rarity = "Common",
		Roles = roles(rgb(255, 215, 80), CREAM, rgb(255, 240, 120), SILVER, rgb(120, 80, 40)),
		Price = { Coins = 1500 },
		Source = "Coins",
	},
	W_Bubblegum = {
		Name = { de = "Kaugummi", en = "Bubblegum" },
		Rarity = "Common",
		Roles = roles(rgb(247, 150, 200), rgb(255, 220, 235), rgb(255, 90, 190), SILVER, rgb(150, 60, 120)),
		Price = { Coins = 3000 },
		Source = "Coins",
	},
	W_Grape = {
		Name = { de = "Traube", en = "Grape" },
		Rarity = "Common",
		Roles = roles(rgb(140, 90, 200), rgb(185, 167, 242), rgb(200, 120, 255), SILVER, rgb(60, 30, 90)),
		Price = { Coins = 3000 },
		Source = "Coins",
	},
	W_Charcoal = {
		Name = { de = "Kohle", en = "Charcoal" },
		Rarity = "Common",
		Roles = roles(CHARCOAL, rgb(70, 70, 82), rgb(255, 140, 40), rgb(120, 120, 130), rgb(25, 25, 30)),
		Price = { Coins = 3000 },
		Source = "Coins",
	},
	-- Rare (Katalog/Kiste)
	W_Ocean = {
		Name = { de = "Ozean", en = "Ocean" },
		Rarity = "Rare",
		Roles = roles(rgb(30, 90, 170), rgb(40, 160, 190), rgb(80, 230, 255), SILVER, rgb(20, 40, 80)),
		Source = "Catalog",
	},
	W_Lemonade = {
		Name = { de = "Limo", en = "Lemonade" },
		Rarity = "Rare",
		Roles = roles(rgb(255, 240, 110), rgb(255, 170, 190), rgb(255, 255, 160), SILVER, rgb(255, 120, 150)),
		Source = "Catalog",
	},
	W_Cherry = {
		Name = { de = "Kirsche", en = "Cherry" },
		Rarity = "Rare",
		Roles = roles(rgb(220, 40, 60), rgb(120, 20, 35), rgb(255, 90, 110), SILVER, rgb(60, 110, 40)),
		Source = "Catalog",
	},
	W_ToyCamo = {
		Name = { de = "Spielzeug-Tarn", en = "Toy Camo" },
		Rarity = "Rare",
		Roles = roles(rgb(110, 140, 70), rgb(150, 110, 70), rgb(230, 210, 150), rgb(90, 95, 80), rgb(70, 60, 40), {
			Accent = "SmoothPlastic",
			Body = "Fabric",
		}),
		Source = "Catalog",
	},
	W_Peach = {
		Name = { de = "Pfirsich", en = "Peach" },
		Rarity = "Rare",
		Roles = roles(rgb(255, 190, 150), rgb(255, 225, 200), rgb(255, 150, 120), SILVER, rgb(170, 100, 80)),
		Source = "Catalog",
	},
	W_Forest = {
		Name = { de = "Wald", en = "Forest" },
		Rarity = "Rare",
		Roles = roles(rgb(40, 100, 55), rgb(120, 85, 50), rgb(140, 220, 90), rgb(90, 80, 60), rgb(70, 50, 30), {
			Detail = "Wood",
			Grip = "WoodPlanks",
		}),
		Source = "Catalog",
	},
	-- Epic
	W_NeonGrid = {
		Name = { de = "Neon-Gitter", en = "Neon Grid" },
		Rarity = "Epic",
		Roles = roles(rgb(20, 20, 35), rgb(40, 30, 70), rgb(255, 60, 220), rgb(0, 230, 255), rgb(15, 15, 25), {
			Metal = "Neon",
		}),
		Anim = "Pulse",
		Source = "Catalog",
	},
	W_Candy = {
		Name = { de = "Zuckerl", en = "Candy" },
		Rarity = "Epic",
		Roles = roles(rgb(255, 120, 190), WHITE, rgb(255, 60, 160), rgb(255, 200, 230), rgb(140, 220, 255), {
			Metal = "Glass",
		}),
		Source = "Catalog",
	},
	W_Frost = {
		Name = { de = "Frost", en = "Frost" },
		Rarity = "Epic",
		Roles = roles(rgb(200, 235, 255), rgb(150, 210, 245), rgb(120, 220, 255), WHITE, rgb(80, 120, 170), {
			Detail = "Glass",
			Metal = "Glass",
		}),
		Source = "Catalog",
	},
	W_Toxic = {
		Name = { de = "Giftgrün", en = "Toxic" },
		Rarity = "Epic",
		Roles = roles(rgb(30, 35, 30), rgb(60, 70, 40), rgb(120, 255, 60), rgb(160, 255, 90), rgb(20, 25, 20), {
			Metal = "Neon",
		}),
		Anim = "Pulse",
		Source = "Catalog",
	},
	-- Legendary
	W_Lava = {
		Name = { de = "Lava", en = "Lava" },
		Rarity = "Legendary",
		Roles = roles(rgb(45, 30, 30), rgb(90, 40, 30), rgb(255, 110, 20), rgb(255, 170, 40), rgb(30, 20, 20), {
			Body = "Slate",
			Metal = "Neon",
		}),
		Anim = { "Pulse", "Sparkle" },
		Source = "Catalog",
	},
	W_Aurora = {
		Name = { de = "Polarlicht", en = "Aurora" },
		Rarity = "Legendary",
		Roles = roles(rgb(80, 255, 180), rgb(30, 40, 80), rgb(120, 200, 255), rgb(200, 120, 255), rgb(20, 25, 50), {
			Metal = "Glass",
		}),
		Anim = "Rainbow",
		Source = "Catalog",
	},
	-- Mythic
	W_Starlight = {
		Name = { de = "Sternenlicht", en = "Starlight" },
		Rarity = "Mythic",
		Roles = roles(rgb(30, 20, 70), rgb(60, 30, 110), rgb(255, 120, 255), rgb(160, 220, 255), rgb(15, 10, 40), {
			Metal = "Neon",
		}),
		Anim = { "Galaxy", "Sparkle" },
		Source = "Catalog",
	},
	-- Sonderquellen
	W_VIPGold = {
		Name = { de = "VIP-Gold", en = "VIP Gold" },
		Rarity = "Legendary",
		Roles = roles(GOLD, rgb(255, 225, 120), rgb(255, 245, 180), rgb(255, 210, 80), rgb(90, 60, 20), {
			Body = "Foil",
			Detail = "Foil",
		}),
		Source = "VIP",
	},
	W_RookieRainbow = {
		Name = { de = "Neuling-Regenbogen", en = "Rookie Rainbow" },
		Rarity = "Epic",
		Roles = roles(rgb(255, 90, 90), rgb(255, 210, 60), rgb(80, 220, 255), rgb(150, 255, 120), rgb(180, 120, 255)),
		Anim = "Rainbow",
		Source = "Starter",
	},
	-- Meisterschaft (B16.2) – nicht kaufbar, Ausrüsten prüft die Stufe DIESER Waffe
	W_MBronze = {
		Name = { de = "Bronze", en = "Bronze" },
		Rarity = "Rare",
		Roles = roles(rgb(205, 127, 50), rgb(160, 95, 40), rgb(240, 170, 100), rgb(180, 110, 50), rgb(70, 40, 20), {
			Body = "Foil",
			Accent = "Foil",
		}),
		Source = "Mastery",
		MasteryTier = 2,
	},
	W_MSilver = {
		Name = { de = "Silber", en = "Silver" },
		Rarity = "Rare",
		Roles = roles(rgb(200, 205, 215), rgb(160, 165, 175), WHITE, rgb(220, 225, 235), rgb(60, 62, 70), {
			Body = "Foil",
			Accent = "Foil",
		}),
		Source = "Mastery",
		MasteryTier = 4,
	},
	W_MGold = {
		Name = { de = "Gold", en = "Gold" },
		Rarity = "Epic",
		Roles = roles(GOLD, rgb(230, 170, 30), rgb(255, 240, 150), rgb(255, 215, 90), rgb(90, 60, 20), {
			Body = "Foil",
			Accent = "Foil",
		}),
		Source = "Mastery",
		MasteryTier = 5,
	},
	W_MDiamond = {
		Name = { de = "Diamant", en = "Diamond" },
		Rarity = "Epic",
		Roles = roles(rgb(185, 240, 255), rgb(140, 220, 250), WHITE, rgb(210, 245, 255), rgb(60, 110, 140), {
			Body = "Glass",
			Detail = "Glass",
			Metal = "Glass",
		}),
		Anim = "Sparkle",
		Source = "Mastery",
		MasteryTier = 7,
	},
	W_MNeon = {
		Name = { de = "Neon-Puls", en = "Neon Pulse" },
		Rarity = "Legendary",
		Roles = roles(rgb(25, 25, 40), rgb(50, 40, 90), rgb(0, 255, 200), rgb(255, 60, 220), rgb(15, 15, 25), {
			Metal = "Neon",
		}),
		Anim = "Pulse",
		Source = "Mastery",
		MasteryTier = 8,
	},
	W_MGalaxy = {
		Name = { de = "Galaxie", en = "Galaxy" },
		Rarity = "Legendary",
		Roles = roles(rgb(40, 20, 90), rgb(20, 30, 80), rgb(255, 120, 255), rgb(120, 200, 255), rgb(15, 10, 40), {
			Metal = "Neon",
		}),
		Anim = "Galaxy",
		Source = "Mastery",
		MasteryTier = 9,
	},
	W_MPrism = {
		Name = { de = "Prisma", en = "Prism" },
		Rarity = "Mythic",
		Roles = roles(
			rgb(255, 120, 200),
			rgb(120, 220, 255),
			rgb(255, 255, 140),
			rgb(170, 255, 170),
			rgb(170, 140, 255),
			{
				Body = "Glass",
				Metal = "Glass",
			}
		),
		Source = "Mastery",
		MasteryTier = 10,
	},
	-- Clutch Pass Saison 1 (Premium-Spur) – exklusiv während Saison 1
	W_S1_Neon = {
		Name = { de = "S1 Neon", en = "S1 Neon" },
		Rarity = "Rare",
		Roles = roles(rgb(35, 30, 60), rgb(255, 60, 170), rgb(0, 230, 255), rgb(255, 120, 220), rgb(20, 18, 35)),
		Source = "Pass",
	},
	W_S1_Sunset = {
		Name = { de = "S1 Sonnenuntergang", en = "S1 Sunset" },
		Rarity = "Rare",
		Roles = roles(rgb(255, 130, 70), rgb(255, 80, 120), rgb(255, 210, 90), rgb(255, 170, 120), rgb(90, 40, 70)),
		Source = "Pass",
	},
	W_S1_Ice = {
		Name = { de = "S1 Eiskristall", en = "S1 Ice Crystal" },
		Rarity = "Epic",
		Roles = roles(rgb(220, 245, 255), rgb(170, 225, 255), rgb(140, 235, 255), WHITE, rgb(90, 140, 190), {
			Body = "Glass",
			Metal = "Glass",
		}),
		Source = "Pass",
	},
	W_S1_Gold = {
		Name = { de = "S1 Gold", en = "S1 Gold" },
		Rarity = "Epic",
		Roles = roles(rgb(255, 205, 60), rgb(255, 60, 170), rgb(255, 245, 170), rgb(255, 220, 110), rgb(60, 30, 50), {
			Body = "Foil",
		}),
		Source = "Pass",
	},
	W_S1_Circuit = {
		Name = { de = "S1 Schaltkreis", en = "S1 Circuit" },
		Rarity = "Epic",
		Roles = roles(rgb(20, 60, 50), rgb(30, 90, 70), rgb(80, 255, 170), rgb(0, 230, 255), rgb(15, 30, 25), {
			Metal = "Neon",
		}),
		Anim = "Pulse",
		Source = "Pass",
	},
	W_S1_Champion = {
		Name = { de = "S1 Champion", en = "S1 Champion" },
		Rarity = "Legendary",
		Roles = roles(rgb(255, 60, 170), rgb(255, 205, 60), rgb(0, 230, 255), rgb(255, 230, 120), rgb(40, 20, 60), {
			Detail = "Foil",
		}),
		Anim = "Rainbow",
		Source = "Pass",
	},
}

-- ---------------------------------------------------------------------
-- 2) SKINS (8) – Rezept in Shared/WeaponModels unter Recipe (= Skin-Id)
-- ---------------------------------------------------------------------
Cosmetics.Skins = {
	S_PopRifle_WaterBlaster = {
		Name = { de = "Wasser-Blaster", en = "Water Blaster" },
		Rarity = "Epic",
		Weapon = "PopRifle",
		Recipe = "S_PopRifle_WaterBlaster",
		Source = "Catalog",
	},
	S_BuzzSMG_HairDryer = {
		Name = { de = "Föhn", en = "Hair Dryer" },
		Rarity = "Epic",
		Weapon = "BuzzSMG",
		Recipe = "S_BuzzSMG_HairDryer",
		Source = "Catalog",
	},
	S_Scatter_BubbleBath = {
		Name = { de = "Schaumbad", en = "Bubble Bath" },
		Rarity = "Rare",
		Weapon = "Scatter",
		Recipe = "S_Scatter_BubbleBath",
		Source = "Catalog",
	},
	S_Longshot_PoolNoodle = {
		Name = { de = "Poolnudel", en = "Pool Noodle" },
		Rarity = "Legendary",
		Weapon = "Longshot",
		Recipe = "S_Longshot_PoolNoodle",
		Source = "Catalog",
	},
	S_BonkHammer_Baguette = {
		Name = { de = "Baguette", en = "Baguette" },
		Rarity = "Legendary",
		Weapon = "BonkHammer",
		Recipe = "S_BonkHammer_Baguette",
		Source = "Catalog",
	},
	S_PopGrenade_RubberDuck = {
		Name = { de = "Quietsche-Ente", en = "Rubber Duck" },
		Rarity = "Mythic",
		Weapon = "PopGrenade",
		Recipe = "S_PopGrenade_RubberDuck",
		Source = "Catalog",
	},
	S_PipPistol_RayGun = {
		Name = { de = "Strahlenpistole", en = "Ray Gun" },
		Rarity = "Epic",
		Weapon = "PipPistol",
		Recipe = "S_PipPistol_RayGun",
		Source = "Pass",
	},
	S_PopRifle_CarrotCannon = {
		Name = { de = "Karotten-Kanone", en = "Carrot Cannon" },
		Rarity = "Legendary",
		Weapon = "PopRifle",
		Recipe = "S_PopRifle_CarrotCannon",
		Source = "Pass",
	},
}

-- ---------------------------------------------------------------------
-- 3) CHARMS (13) – Rezept in Shared/CosmeticModels unter Recipe (= Charm-Id)
-- ---------------------------------------------------------------------
Cosmetics.Charms = {
	C_Duck = { Name = { de = "Ente", en = "Duck" }, Rarity = "Common", Recipe = "C_Duck", Source = "Catalog" },
	C_Dice = { Name = { de = "Würfel", en = "Dice" }, Rarity = "Common", Recipe = "C_Dice", Source = "Catalog" },
	C_Star = { Name = { de = "Stern", en = "Star" }, Rarity = "Common", Recipe = "C_Star", Source = "Catalog" },
	C_Heart = { Name = { de = "Herz", en = "Heart" }, Rarity = "Common", Recipe = "C_Heart", Source = "Catalog" },
	C_Donut = { Name = { de = "Donut", en = "Donut" }, Rarity = "Common", Recipe = "C_Donut", Source = "Catalog" },
	C_MiniRocket = {
		Name = { de = "Mini-Rakete", en = "Mini Rocket" },
		Rarity = "Rare",
		Recipe = "C_MiniRocket",
		Source = "Catalog",
	},
	C_CubeBuddy = {
		Name = { de = "Würfel-Kumpel", en = "Cube Buddy" },
		Rarity = "Rare",
		Recipe = "C_CubeBuddy",
		Source = "Catalog",
	},
	C_Ghost = { Name = { de = "Geist", en = "Ghost" }, Rarity = "Rare", Recipe = "C_Ghost", Source = "Pass" },
	C_Crown = { Name = { de = "Krone", en = "Crown" }, Rarity = "Epic", Recipe = "C_Crown", Source = "Pass" },
	C_Cactus = { Name = { de = "Kaktus", en = "Cactus" }, Rarity = "Epic", Recipe = "C_Cactus", Source = "Pass" },
	C_Trophy = { Name = { de = "Pokal", en = "Trophy" }, Rarity = "Legendary", Recipe = "C_Trophy", Source = "Pass" },
	C_CalendarCat = {
		Name = { de = "Kalender-Katze", en = "Calendar Cat" },
		Rarity = "Epic",
		Recipe = "C_CalendarCat",
		Source = "Login",
	},
	C_StarterStar = {
		Name = { de = "Starter-Stern", en = "Starter Star" },
		Rarity = "Rare",
		Recipe = "C_StarterStar",
		Source = "Starter",
	},
}

-- ---------------------------------------------------------------------
-- 4) FINISHER (8) – Builder in Client/Modules/Finishers unter Builder (= Finisher-Id)
--    ≤ 25 Teile/Partikel, ≤ 2.5 s, > 300 Studs ausgeblendet, max. 4 gleichzeitig
-- ---------------------------------------------------------------------
Cosmetics.Finishers = {
	F_Confetti = {
		Name = { de = "Konfetti", en = "Confetti" },
		Rarity = "Common",
		Builder = "F_Confetti",
		Source = "Default",
	},
	F_PixelBurst = {
		Name = { de = "Pixel-Explosion", en = "Pixel Burst" },
		Rarity = "Rare",
		Builder = "F_PixelBurst",
		Source = "Catalog",
	},
	F_IceCube = {
		Name = { de = "Eiswürfel", en = "Ice Cube" },
		Rarity = "Epic",
		Builder = "F_IceCube",
		Source = "Catalog",
	},
	F_BalloonFloat = {
		Name = { de = "Ballonflug", en = "Balloon Float" },
		Rarity = "Epic",
		Builder = "F_BalloonFloat",
		Source = "Pass",
	},
	F_GoldStatue = {
		Name = { de = "Goldstatue", en = "Gold Statue" },
		Rarity = "Legendary",
		Builder = "F_GoldStatue",
		Source = "Catalog",
	},
	F_RainbowPuff = {
		Name = { de = "Regenbogen-Puff", en = "Rainbow Puff" },
		Rarity = "Legendary",
		Builder = "F_RainbowPuff",
		Source = "Pass",
	},
	F_DuckRain = {
		Name = { de = "Entenregen", en = "Duck Rain" },
		Rarity = "Mythic",
		Builder = "F_DuckRain",
		Source = "Catalog",
	},
	F_CrownConfetti = {
		Name = { de = "Kronen-Konfetti", en = "Crown Confetti" },
		Rarity = "Legendary",
		Builder = "F_CrownConfetti",
		Source = "VIP",
	},
}

-- ---------------------------------------------------------------------
-- 5) TRACER (6) – Helligkeit ≥ 0.5, Transparenz ≤ 0.3 (CosmeticModels.TracerStyle)
--    Color = Color3 | "Team" (Teamfarbe des Schützen) | "Rainbow"
-- ---------------------------------------------------------------------
local GRADIENT = "rbxasset://textures/gradient.png"

Cosmetics.Tracers = {
	T_Team = {
		Name = { de = "Teamfarbe", en = "Team Color" },
		Rarity = "Common",
		Color = "Team",
		Width0 = 0.12,
		Width1 = 0.05,
		Texture = GRADIENT,
		Sparkle = false,
		Source = "Default",
	},
	T_Gold = {
		Name = { de = "Goldspur", en = "Gold Trail" },
		Rarity = "Rare",
		Color = rgb(255, 205, 60),
		Width0 = 0.14,
		Width1 = 0.06,
		Texture = GRADIENT,
		Sparkle = false,
		Source = "Catalog",
	},
	T_Bubble = {
		Name = { de = "Seifenblase", en = "Bubble" },
		Rarity = "Rare",
		Color = rgb(150, 230, 255),
		Width0 = 0.2,
		Width1 = 0.1,
		Texture = GRADIENT,
		Sparkle = true,
		Source = "Catalog",
	},
	T_LaserPink = {
		Name = { de = "Laser-Pink", en = "Laser Pink" },
		Rarity = "Epic",
		Color = rgb(255, 60, 200),
		Width0 = 0.1,
		Width1 = 0.1,
		Texture = "",
		Sparkle = false,
		Source = "Catalog",
	},
	T_Zigzag = {
		Name = { de = "Zickzack", en = "Zigzag" },
		Rarity = "Epic",
		Color = rgb(120, 255, 120),
		Width0 = 0.12,
		Width1 = 0.12,
		Texture = "",
		Sparkle = false,
		Zigzag = true,
		Source = "Pass",
	},
	T_Rainbow = {
		Name = { de = "Regenbogen", en = "Rainbow" },
		Rarity = "Legendary",
		Color = "Rainbow",
		Width0 = 0.16,
		Width1 = 0.08,
		Texture = GRADIENT,
		Sparkle = true,
		Source = "Pass",
	},
}

-- ---------------------------------------------------------------------
-- 6) TITEL (Ids "TT_…") – Meisterschafts-Titel werden per Schleife erzeugt
-- ---------------------------------------------------------------------
Cosmetics.Titles = {
	TT_Lv10 = { Name = { de = "Kein Neuling mehr", en = "Rookie No More" }, Source = "Earned" },
	TT_Lv25 = { Name = { de = "Scharfschütze", en = "Sharpshooter" }, Source = "Earned" },
	TT_Lv50 = { Name = { de = "Veteran", en = "Veteran" }, Source = "Earned", Color = rgb(170, 90, 255) },
	TT_Lv75 = { Name = { de = "Elite", en = "Elite" }, Source = "Earned", Color = rgb(255, 150, 40) },
	TT_Lv100 = { Name = { de = "Clutch-Legende", en = "Clutch Legend" }, Source = "Earned", Color = GOLD },
	-- Erfolge (B16.5)
	TT_FirstPop = { Name = { de = "Erster Pop", en = "First Pop" }, Source = "Earned" },
	TT_Headhunter = { Name = { de = "Kopfjäger", en = "Headhunter" }, Source = "Earned" },
	TT_Untouchable = { Name = { de = "Unberührbar", en = "Untouchable" }, Source = "Earned" },
	TT_ClutchMaster = { Name = { de = "Clutch-Meister", en = "Clutch Master" }, Source = "Earned" },
	TT_Ace = { Name = { de = "Ass", en = "Ace" }, Source = "Earned" },
	TT_ThroneKeeper = { Name = { de = "Kronen-Hüter", en = "Throne Keeper" }, Source = "Earned" },
	TT_BountyHunter = { Name = { de = "Kopfgeldjäger", en = "Bounty Hunter" }, Source = "Earned" },
	TT_Collector = { Name = { de = "Sammler", en = "Collector" }, Source = "Earned" },
	TT_Arsenal = { Name = { de = "Arsenal", en = "Arsenal" }, Source = "Earned" },
	TT_GoodSport = { Name = { de = "Fairer Sportler", en = "Good Sport" }, Source = "Earned" },
	TT_Marathon = { Name = { de = "Marathon", en = "Marathon" }, Source = "Earned" },
	TT_SkyDiver = { Name = { de = "Himmelstaucher", en = "Sky Diver" }, Source = "Earned" },
	-- Käufe / Pass / Login
	TT_Frischling = { Name = { de = "Frischling", en = "Fresh Face" }, Source = "Starter" },
	TT_VIP = { Name = { de = "VIP", en = "VIP" }, Source = "VIP", Color = GOLD },
	TT_Supporter = { Name = { de = "Unterstützer", en = "Supporter" }, Source = "Earned", Color = rgb(255, 90, 140) },
	TT_S1Veteran = { Name = { de = "S1-Veteran", en = "S1 Veteran" }, Source = "Pass" },
	TT_PassHolderS1 = { Name = { de = "Pass-Inhaber S1", en = "S1 Pass Holder" }, Source = "Pass" },
	TT_PartyStarter = { Name = { de = "Party-Starter", en = "Party Starter" }, Source = "Earned" },
	TT_OnFire = { Name = { de = "Brennt!", en = "On Fire" }, Source = "Earned", Color = rgb(255, 120, 40) },
}
-- 15 × "<Waffe>-Meister" (Meisterschaft Stufe IX)
for _, w in ipairs(WEAPONS) do
	Cosmetics.Titles["TT_Master_" .. w.Key] = {
		Name = { de = w.de .. "-Meister", en = w.en .. " Master" },
		Source = "Mastery",
		Weapon = w.Key,
		Color = GOLD,
	}
end

-- ---------------------------------------------------------------------
-- 7) EXKLUSIV – Pass-Items: während ihrer Saison (Id) nur über den Pass,
--    nicht im Katalog/in Kisten. Ab der nächsten Saison im Katalog.
-- ---------------------------------------------------------------------
Cosmetics.Exclusive = {
	S_PipPistol_RayGun = 1,
	S_PopRifle_CarrotCannon = 1,
	W_S1_Neon = 1,
	W_S1_Sunset = 1,
	W_S1_Ice = 1,
	W_S1_Gold = 1,
	W_S1_Circuit = 1,
	W_S1_Champion = 1,
	C_Ghost = 1,
	C_Crown = 1,
	C_Cactus = 1,
	C_Trophy = 1,
	F_BalloonFloat = 1,
	F_RainbowPuff = 1,
	T_Zigzag = 1,
	T_Rainbow = 1,
}

-- =====================================================================
-- 8) NACHSCHLAGEN – ById mit Kind und Id (doppelte Ids = Fehler beim Laden)
-- =====================================================================
Cosmetics.ById = {} :: { [string]: any }

local KIND_TABLES = {
	{ Kind = "Wrap", List = Cosmetics.Wraps },
	{ Kind = "Skin", List = Cosmetics.Skins },
	{ Kind = "Charm", List = Cosmetics.Charms },
	{ Kind = "Finisher", List = Cosmetics.Finishers },
	{ Kind = "Tracer", List = Cosmetics.Tracers },
	{ Kind = "Title", List = Cosmetics.Titles },
}

for _, entry in ipairs(KIND_TABLES) do
	for id, def in pairs(entry.List :: { [string]: any }) do
		assert(Cosmetics.ById[id] == nil, "[Config.Cosmetics] Doppelte Kosmetik-Id: " .. id)
		def.Id = id
		def.Kind = entry.Kind
		Cosmetics.ById[id] = def
	end
end

function Cosmetics.Get(id: string): any
	if type(id) ~= "string" then
		return nil
	end
	return Cosmetics.ById[id]
end

-- Pass-Item, dessen Saison noch läuft (oder noch nicht vorbei ist)? -> nicht im Katalog/Splitter-Shop
function Cosmetics.IsExclusive(id: string, seasonId: number): boolean
	local season = Cosmetics.Exclusive[id]
	if season == nil then
		return false
	end
	return (tonumber(seasonId) or 1) <= season
end

-- Anim als Liste (Config erlaubt Text oder Liste)
function Cosmetics.AnimList(def: any): { string }
	local anim = def and def.Anim
	if type(anim) == "string" then
		return { anim }
	elseif type(anim) == "table" then
		return anim
	end
	return {}
end

-- =====================================================================
-- 9) PRÜFEN (Config.Validate sammelt das; leere Liste = alles ok)
-- =====================================================================
local SOURCES = {
	Catalog = true,
	Coins = true,
	Pass = true,
	VIP = true,
	Starter = true,
	Mastery = true,
	Login = true,
	Default = true,
	Earned = true,
}

local function checkName(errors: { string }, path: string, name: any)
	if type(name) ~= "table" or type(name.de) ~= "string" or type(name.en) ~= "string" then
		table.insert(errors, path .. ".Name: { de, en } erwartet")
	elseif name.de == "" or name.en == "" then
		table.insert(errors, path .. ".Name: leerer Text")
	end
end

function Cosmetics.Validate(Config: any): { string }
	local errors: { string } = {}
	local weaponSet: { [string]: boolean } = {}
	for _, key in ipairs(Cosmetics.WeaponKeys) do
		weaponSet[key] = true
	end
	for _, entry in ipairs(KIND_TABLES) do
		for id, def in pairs(entry.List :: { [string]: any }) do
			local path = ("Config.Cosmetics.%ss.%s"):format(entry.Kind, id)
			checkName(errors, path, def.Name)
			if not SOURCES[def.Source] then
				table.insert(errors, path .. ".Source: unbekannte Quelle " .. tostring(def.Source))
			end
			if entry.Kind ~= "Title" and Cosmetics.RarityRank[def.Rarity] == nil then
				table.insert(errors, path .. ".Rarity: Common/Rare/Epic/Legendary/Mythic erwartet")
			end
			if def.Price ~= nil then
				local coins = type(def.Price) == "table" and def.Price.Coins
				if type(coins) ~= "number" or coins <= 0 or coins % 1 ~= 0 then
					table.insert(errors, path .. ".Price: { Coins = ganze Zahl > 0 } oder nil erwartet")
				end
			end
		end
	end
	-- Wraps: Rollen + Material (nie Ice) + Anim
	for id, def in pairs(Cosmetics.Wraps :: { [string]: any }) do
		local path = "Config.Cosmetics.Wraps." .. id
		for _, role in ipairs(Cosmetics.WrapRoles) do
			local r = def.Roles and def.Roles[role]
			if type(r) ~= "table" or typeof(r.Color) ~= "Color3" then
				table.insert(errors, ("%s.Roles.%s: { Color = Color3, Material } erwartet"):format(path, role))
			elseif not Cosmetics.Materials[r.Material] then
				table.insert(
					errors,
					("%s.Roles.%s.Material: nicht erlaubt (%s)"):format(path, role, tostring(r.Material))
				)
			end
		end
		if def.Roles and def.Roles.Tip ~= nil then
			table.insert(errors, path .. ".Roles.Tip: die orange Spitze darf kein Wrap verändern")
		end
		for _, anim in ipairs(Cosmetics.AnimList(def)) do
			if not Cosmetics.Anims[anim] then
				table.insert(errors, path .. ".Anim: unbekannt " .. tostring(anim))
			end
		end
		if def.Source == "Mastery" and (type(def.MasteryTier) ~= "number" or def.MasteryTier < 1) then
			table.insert(errors, path .. ".MasteryTier: Zahl ≥ 1 erwartet")
		end
	end
	-- Skins: Waffe muss existieren (+ Rezept in WeaponModels, falls schon vorhanden)
	local weaponModels: any = nil
	local ok, shared = pcall(function()
		return script.Parent.Parent
	end)
	if ok and typeof(shared) == "Instance" then
		local module = shared:FindFirstChild("WeaponModels")
		if module and module:IsA("ModuleScript") then
			local loaded, result = pcall(require, module)
			if loaded and type(result) == "table" then
				weaponModels = result
			end
		end
	end
	for id, def in pairs(Cosmetics.Skins :: { [string]: any }) do
		local path = "Config.Cosmetics.Skins." .. id
		if not weaponSet[def.Weapon] then
			table.insert(errors, path .. ".Weapon: unbekannte Waffe " .. tostring(def.Weapon))
		elseif Config and type(Config.Weapon) == "function" and type(Config.Weapons) == "table" then
			if type(Config.Weapons.List) == "table" and Config.Weapon(def.Weapon) == nil then
				table.insert(errors, path .. ".Weapon: fehlt in Config.Weapons")
			end
		end
		if weaponModels and type(weaponModels.HasRecipe) == "function" then
			local has, result = pcall(weaponModels.HasRecipe, def.Recipe)
			if has and result ~= true then
				table.insert(errors, path .. ".Recipe: kein Rezept in WeaponModels (" .. tostring(def.Recipe) .. ")")
			end
		end
	end
	-- Tracer: Helligkeit ≥ 0.5, Breiten > 0
	for id, def in pairs(Cosmetics.Tracers :: { [string]: any }) do
		local path = "Config.Cosmetics.Tracers." .. id
		if typeof(def.Color) == "Color3" then
			local _, _, v = def.Color:ToHSV()
			if v < 0.5 then
				table.insert(errors, path .. ".Color: Helligkeit ≥ 0.5 erwartet")
			end
		elseif def.Color ~= "Team" and def.Color ~= "Rainbow" then
			table.insert(errors, path .. '.Color: Color3, "Team" oder "Rainbow" erwartet')
		end
		if type(def.Width0) ~= "number" or type(def.Width1) ~= "number" or def.Width0 <= 0 or def.Width1 <= 0 then
			table.insert(errors, path .. ".Width0/Width1: Zahlen > 0 erwartet")
		end
		if def.Texture ~= "" and def.Texture ~= GRADIENT then
			table.insert(errors, path .. '.Texture: nur gradient.png oder "" (ASSETS.md)')
		end
	end
	-- Exklusiv: nur Pass-Items, Saison-Id ≥ 1
	for id, season in pairs(Cosmetics.Exclusive :: { [string]: number }) do
		local def = Cosmetics.ById[id]
		if def == nil then
			table.insert(errors, "Config.Cosmetics.Exclusive." .. id .. ": unbekannte Id")
		elseif def.Source ~= "Pass" then
			table.insert(errors, "Config.Cosmetics.Exclusive." .. id .. ": nur Pass-Items sind exklusiv")
		end
		if type(season) ~= "number" or season < 1 then
			table.insert(errors, "Config.Cosmetics.Exclusive." .. id .. ": Saison-Id ≥ 1 erwartet")
		end
	end
	for id, def in pairs(Cosmetics.ById) do
		if def.Source == "Pass" and def.Kind ~= "Title" and Cosmetics.Exclusive[id] == nil then
			table.insert(errors, "Config.Cosmetics: Pass-Item " .. id .. " fehlt in Exclusive")
		end
	end
	-- Standard-Items vorhanden
	for kind, id in pairs(Cosmetics.Defaults) do
		local def = Cosmetics.ById[id]
		if def == nil or def.Kind ~= kind then
			table.insert(errors, ("Config.Cosmetics.Defaults.%s: %s fehlt"):format(kind, tostring(id)))
		end
	end
	return errors
end

return Cosmetics
