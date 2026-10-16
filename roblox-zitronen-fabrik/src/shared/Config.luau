--[[
	Zitronen-Fabrik Tycoon – zentrale Einstellungen.

	Hier kannst du fast alles anpassen: Preise, Namen, Farben, Events,
	Gamepass-IDs und Sounds. Alle anderen Skripte lesen ihre Werte von hier.
]]

local Config = {}

Config.GameName = "Zitronen-Fabrik Tycoon"
Config.DataStoreName = "ZitronenFabrik_v1"
Config.LeaderboardStoreName = "ZitronenFabrik_Reichste_v1"

Config.StartCash = 1 -- Papa schenkt dir 1 $ für deinen ersten Stand
Config.MaxPlots = 6 -- Fabriken auf der Insel (= maximale Spieler pro Server)
Config.MaxLevel = 1000
Config.MinCycleTime = 0.05
Config.AutosaveInterval = 90
Config.WalkSpeed = 22

-- Förderband-Optik (nur Anzeige, die Einnahmen rechnet der Server)
Config.Visual = {
	MaxTravel = 7, -- Sekunden, die eine Frucht höchstens über das Band fährt
	MinTravel = 2.5, -- Sekunden, die eine Frucht mindestens fährt (wenn ein Manager arbeitet)
	OwnMinInterval = 0.2, -- höchstens 5 Früchte pro Sekunde und Linie (eigene Fabrik)
	OtherMinInterval = 0.6, -- andere Fabriken etwas sparsamer
	OtherRenderDistance = 260,
}

--------------------------------------------------------------------------
-- Früchte (Evolution). Jede Evolution verwandelt alle Früchte!
--------------------------------------------------------------------------
Config.Fruits = {
	{ Name = "Zitrone", Emoji = "🍋", Color = Color3.fromRGB(255, 221, 25), Material = Enum.Material.SmoothPlastic },
	{ Name = "Orange", Emoji = "🍊", Color = Color3.fromRGB(255, 140, 20), Material = Enum.Material.SmoothPlastic },
	{ Name = "Limette", Emoji = "🍏", Color = Color3.fromRGB(120, 220, 40), Material = Enum.Material.SmoothPlastic },
	{ Name = "Drachenfrucht", Emoji = "🐉", Color = Color3.fromRGB(255, 60, 170), Material = Enum.Material.SmoothPlastic },
	{ Name = "Sternfrucht", Emoji = "⭐", Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Neon },
	{ Name = "Galaxie-Frucht", Emoji = "🌌", Color = Color3.fromRGB(150, 70, 255), Material = Enum.Material.Neon },
}

--------------------------------------------------------------------------
-- Meilensteine: ab diesen Leveln läuft eine Linie schneller / bringt mehr
--------------------------------------------------------------------------
Config.Milestones = {
	{ Level = 25, Speed = 2 },
	{ Level = 50, Speed = 2 },
	{ Level = 100, Speed = 2 },
	{ Level = 200, Speed = 2 },
	{ Level = 300, Speed = 2 },
	{ Level = 400, Speed = 2 },
	{ Level = 500, Revenue = 4 },
	{ Level = 600, Revenue = 4 },
	{ Level = 700, Revenue = 4 },
	{ Level = 800, Revenue = 4 },
	{ Level = 900, Revenue = 4 },
	{ Level = 1000, Revenue = 10 },
}

--------------------------------------------------------------------------
-- Die 6 Förderband-Linien deiner Fabrik
-- Kind: "Egg" (Ei-/Zitronenform), "Ball", "Cylinder" (stehend), "Coin" (flach), "Block", "Gem"
-- Color = "Fruit" heißt: Farbe der aktuellen Frucht
--------------------------------------------------------------------------
Config.Lanes = {
	{
		Id = "stand",
		Name = "Zitronen-Stand",
		Emoji = "🍋",
		Theme = "Stand",
		Color = Color3.fromRGB(255, 205, 40),
		BaseCost = 1,
		CostGrowth = 1.08,
		BaseRevenue = 1,
		CycleTime = 1.2,
		ManagerCost = 2500,
		Manager = { Name = "Limonino Spremitore", Shirt = Color3.fromRGB(255, 220, 40), Hat = "Lemon" },
		Upgraders = {
			{ Name = "Waschanlage", Mult = 2, Cost = 250, Color = Color3.fromRGB(80, 170, 255) },
			{ Name = "Saftpresse", Mult = 3, Cost = 62500, Color = Color3.fromRGB(255, 150, 30) },
			{ Name = "Eis-Kühler", Mult = 5, Cost = 12500000, Color = Color3.fromRGB(150, 230, 255) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.5, 1.15, 1.15), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Egg", Size = Vector3.new(1.5, 1.15, 1.15), Color = "Fruit", Material = Enum.Material.Glass },
			{ Kind = "Cylinder", Size = Vector3.new(1.6, 1.2, 1.2), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Cylinder", Size = Vector3.new(1.6, 1.3, 1.3), Color = Color3.fromRGB(190, 235, 255), Material = Enum.Material.Ice },
		},
		UpgradeNames = { "Saurere Zitronen", "Extra Zucker", "Bio-Zitronen", "Kristall-Gläser", "Omas Geheimrezept", "Diamant-Strohhalme", "Gold-Becher", "Limo-Legende" },
	},
	{
		Id = "delivery",
		Name = "Limo-Lieferdienst",
		Emoji = "🚚",
		Theme = "Delivery",
		Color = Color3.fromRGB(255, 90, 60),
		BaseCost = 75,
		CostGrowth = 1.15,
		BaseRevenue = 60,
		CycleTime = 3,
		ManagerCost = 50000,
		Manager = { Name = "Bottiglio Velocino", Shirt = Color3.fromRGB(230, 60, 50), Hat = "Cap" },
		Upgraders = {
			{ Name = "Abfüllanlage", Mult = 2, Cost = 6250, Color = Color3.fromRGB(90, 200, 255) },
			{ Name = "Etikettierer", Mult = 3, Cost = 1250000, Color = Color3.fromRGB(255, 80, 80) },
			{ Name = "Kisten-Packer", Mult = 5, Cost = 250000000, Color = Color3.fromRGB(170, 120, 70) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.5, 1.15, 1.15), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Cylinder", Size = Vector3.new(2.2, 0.9, 0.9), Color = "Fruit", Material = Enum.Material.Glass },
			{ Kind = "Cylinder", Size = Vector3.new(2.2, 0.95, 0.95), Color = Color3.fromRGB(230, 50, 50), Material = Enum.Material.SmoothPlastic },
			{ Kind = "Block", Size = Vector3.new(2, 1.6, 2), Color = Color3.fromRGB(160, 110, 60), Material = Enum.Material.WoodPlanks },
		},
		UpgradeNames = { "Schnellere Roller", "Express-Boxen", "Lieferdrohnen", "Turbo-Trucks", "Raketen-Kuriere", "Teleport-Pakete", "Zeitreise-Post", "Wurmloch-Express" },
	},
	{
		Id = "depot",
		Name = "Saft-Depot",
		Emoji = "🏭",
		Theme = "Depot",
		Color = Color3.fromRGB(70, 200, 90),
		BaseCost = 1500,
		CostGrowth = 1.14,
		BaseRevenue = 900,
		CycleTime = 8,
		ManagerCost = 750000,
		Manager = { Name = "Cassettone Forzuto", Shirt = Color3.fromRGB(60, 160, 70), Hat = "Helmet" },
		Upgraders = {
			{ Name = "Sortier-Laser", Mult = 2, Cost = 100000, Color = Color3.fromRGB(255, 60, 60) },
			{ Name = "Karton-Maschine", Mult = 3, Cost = 20000000, Color = Color3.fromRGB(200, 160, 110) },
			{ Name = "Paletten-Roboter", Mult = 5, Cost = 5000000000, Color = Color3.fromRGB(120, 120, 140) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.7, 1.3, 1.3), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Ball", Size = Vector3.new(2, 2, 2), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Block", Size = Vector3.new(2.2, 1.6, 2.2), Color = Color3.fromRGB(195, 150, 100), Material = Enum.Material.Cardboard },
			{ Kind = "Block", Size = Vector3.new(3, 2, 3), Color = Color3.fromRGB(150, 105, 60), Material = Enum.Material.WoodPlanks },
		},
		UpgradeNames = { "Größere Regale", "Gabelstapler", "Roboter-Lager", "Mega-Hallen", "Kühl-Silos", "Quanten-Lager", "Mond-Lager", "Unendlich-Regal" },
	},
	{
		Id = "lab",
		Name = "Zitronen-Labor",
		Emoji = "🧪",
		Theme = "Lab",
		Color = Color3.fromRGB(80, 160, 255),
		BaseCost = 30000,
		CostGrowth = 1.13,
		BaseRevenue = 12000,
		CycleTime = 20,
		ManagerCost = 12000000,
		Manager = { Name = "Dottor Acidello", Shirt = Color3.fromRGB(245, 245, 245), Hat = "Goggles" },
		Upgraders = {
			{ Name = "Mutations-Strahl", Mult = 2, Cost = 1500000, Color = Color3.fromRGB(80, 255, 120) },
			{ Name = "Kristallisator", Mult = 3, Cost = 375000000, Color = Color3.fromRGB(120, 230, 255) },
			{ Name = "Plasma-Kammer", Mult = 5, Cost = 100000000000, Color = Color3.fromRGB(200, 90, 255) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.5, 1.15, 1.15), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Egg", Size = Vector3.new(1.6, 1.25, 1.25), Color = "Fruit", Material = Enum.Material.Neon },
			{ Kind = "Gem", Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.Glass },
			{ Kind = "Ball", Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(200, 90, 255), Material = Enum.Material.ForceField },
		},
		UpgradeNames = { "Mikroskope", "Zitronen-DNA", "Klon-Tanks", "Mutagen", "Zeitmaschine", "Multiversum-Zitrone", "Atom-Zitrone", "Gott-Formel" },
	},
	{
		Id = "stocks",
		Name = "Zitronen-Börse",
		Emoji = "📈",
		Theme = "Stocks",
		Color = Color3.fromRGB(255, 170, 0),
		BaseCost = 750000,
		CostGrowth = 1.12,
		BaseRevenue = 200000,
		CycleTime = 45,
		ManagerCost = 300000000,
		Manager = { Name = "Soldino Milionario", Shirt = Color3.fromRGB(40, 40, 50), Hat = "TopHat" },
		Upgraders = {
			{ Name = "Münzpresse", Mult = 2, Cost = 37500000, Color = Color3.fromRGB(255, 200, 40) },
			{ Name = "Goldschmelze", Mult = 3, Cost = 10000000000, Color = Color3.fromRGB(255, 120, 20) },
			{ Name = "Diamant-Presse", Mult = 5, Cost = 2500000000000, Color = Color3.fromRGB(150, 240, 255) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.5, 1.15, 1.15), Color = "Fruit", Material = Enum.Material.SmoothPlastic },
			{ Kind = "Coin", Size = Vector3.new(0.4, 1.9, 1.9), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil },
			{ Kind = "Block", Size = Vector3.new(2.2, 0.8, 1.1), Color = Color3.fromRGB(255, 190, 30), Material = Enum.Material.Foil },
			{ Kind = "Gem", Size = Vector3.new(1.5, 1.5, 1.5), Color = Color3.fromRGB(150, 240, 255), Material = Enum.Material.Glass },
		},
		UpgradeNames = { "Aktien-Tipps", "Insider-Zitronen", "Hedgefonds", "Krypto-Zitrone", "Börsen-Monopol", "Welt-Zitronen-Bank", "Mars-Börse", "Galaxie-Fonds" },
	},
	{
		Id = "space",
		Name = "Weltraum-Plantage",
		Emoji = "🛸",
		Theme = "Space",
		Color = Color3.fromRGB(170, 90, 255),
		BaseCost = 25000000,
		CostGrowth = 1.11,
		BaseRevenue = 4000000,
		CycleTime = 120,
		ManagerCost = 8000000000,
		Manager = { Name = "Alieno Agrumino", Shirt = Color3.fromRGB(120, 60, 200), Hat = "Antenna" },
		Upgraders = {
			{ Name = "Antigrav-Ring", Mult = 2, Cost = 1250000000, Color = Color3.fromRGB(90, 255, 200) },
			{ Name = "Sternen-Destille", Mult = 3, Cost = 375000000000, Color = Color3.fromRGB(255, 230, 90) },
			{ Name = "Schwarzes Loch", Mult = 5, Cost = 100000000000000, Color = Color3.fromRGB(40, 20, 60) },
		},
		Items = {
			{ Kind = "Egg", Size = Vector3.new(1.6, 1.2, 1.2), Color = "Fruit", Material = Enum.Material.Neon },
			{ Kind = "Ball", Size = Vector3.new(1.8, 1.8, 1.8), Color = Color3.fromRGB(90, 255, 200), Material = Enum.Material.ForceField },
			{ Kind = "Ball", Size = Vector3.new(1.8, 1.8, 1.8), Color = Color3.fromRGB(255, 230, 90), Material = Enum.Material.Neon },
			{ Kind = "Ball", Size = Vector3.new(2.2, 2.2, 2.2), Color = Color3.fromRGB(25, 10, 45), Material = Enum.Material.Neon },
		},
		UpgradeNames = { "Mond-Erde", "Mars-Gewächshaus", "Asteroiden-Dünger", "Sternenstaub", "Galaxie-Plantage", "Universum-Zitrone", "Urknall-Kern", "Ewige Zitrone" },
	},
}

--------------------------------------------------------------------------
-- Geld-Upgrades (Upgrade-Menü). Werden automatisch erzeugt.
--------------------------------------------------------------------------
Config.CashUpgradeSettings = {
	Tiers = 8,
	BaseCost = 500000,
	TierGrowth = 1000,
	LaneFactor = { 1, 3, 10, 40, 150, 600 },
	AllFactor = 1500,
	InvestorFactor = 4000,
	LaneMult = 3,
	AllMult = 3,
	InvestorAdd = 0.01, -- +1 % pro Investor
	AllNames = { "Zitronen-Fieber", "Sauer macht reich", "Zitronen-Imperium", "Gelbe Revolution", "Zitronen-Gott", "Unendlich sauer", "Zitronen-Universum", "Die letzte Zitrone" },
	InvestorNames = { "Alien-Kaffeekränzchen", "Alien-Golfclub", "Alien-Jacht", "Alien-Insel", "Alien-Planet", "Alien-Galaxie", "Alien-Multiversum", "Alien-Gottheit" },
}

do
	local s = Config.CashUpgradeSettings
	local list = {}
	for tier = 1, s.Tiers do
		local tierCost = s.BaseCost * s.TierGrowth ^ (tier - 1)
		for laneIndex, lane in ipairs(Config.Lanes) do
			table.insert(list, {
				Id = "l" .. laneIndex .. "_" .. tier,
				Name = lane.UpgradeNames[tier] or (lane.Name .. " " .. tier),
				Description = lane.Name .. " bringt " .. s.LaneMult .. "× so viel",
				Emoji = lane.Emoji,
				Cost = tierCost * s.LaneFactor[laneIndex],
				Lane = laneIndex,
				Mult = s.LaneMult,
			})
		end
		table.insert(list, {
			Id = "all_" .. tier,
			Name = s.AllNames[tier],
			Description = "Alle Linien bringen " .. s.AllMult .. "× so viel",
			Emoji = "🌟",
			Cost = tierCost * s.AllFactor,
			Lane = 0,
			Mult = s.AllMult,
		})
		table.insert(list, {
			Id = "inv_" .. tier,
			Name = s.InvestorNames[tier],
			Description = "Jeder Investor bringt +" .. math.floor(s.InvestorAdd * 100 + 0.5) .. " % mehr",
			Emoji = "🛸",
			Cost = tierCost * s.InvestorFactor,
			InvestorAdd = s.InvestorAdd,
		})
	end
	table.sort(list, function(a, b)
		return a.Cost < b.Cost
	end)
	Config.CashUpgrades = list
	Config.CashUpgradeById = {}
	for _, u in ipairs(list) do
		Config.CashUpgradeById[u.Id] = u
	end
end

--------------------------------------------------------------------------
-- Deko (Knopf vorne in der Fabrik). Jede Deko gibt +Bonus auf alles.
--------------------------------------------------------------------------
Config.DecorBonus = 0.05
Config.Decor = {
	{ Id = "fence", Name = "Holzzaun", Emoji = "🪵", Cost = 150 },
	{ Id = "flowers", Name = "Blumenbeete", Emoji = "🌷", Cost = 5000 },
	{ Id = "lamps", Name = "Laternen", Emoji = "💡", Cost = 120000 },
	{ Id = "palms", Name = "Palmen", Emoji = "🌴", Cost = 4000000 },
	{ Id = "fountain", Name = "Zitronen-Brunnen", Emoji = "⛲", Cost = 250000000 },
	{ Id = "statue", Name = "Riesen-Zitrone", Emoji = "🍋", Cost = 50000000000 },
}

--------------------------------------------------------------------------
-- Rebirth mit Alien-Investoren (wie bei Sell Lemons: Zorp der Alien)
--------------------------------------------------------------------------
Config.Rebirth = {
	-- Investoren gesamt = 10 * (Einnahmen seit Evolution / 1 Mrd.) ^ (1/3)
	Coefficient = 10,
	Divisor = 1e9,
	Exponent = 1 / 3,
	BonusPerInvestor = 0.02, -- jeder Investor = +2 % Einnahmen
	MinInvestors = 1,
}

-- Alien-Kräfte: kosten Investoren (die dann nicht mehr als Bonus zählen!)
Config.Powers = {
	{ Id = "turbo", Name = "Turbo-Bänder", Emoji = "⚡", Description = "Alle Linien +25 % schneller", BaseCost = 25, Growth = 4, Max = 5, Value = 1.25 },
	{ Id = "start", Name = "Papas Taschengeld", Emoji = "💼", Description = "Startgeld nach jedem Rebirth", BaseCost = 10, Growth = 5, Max = 5, Value = 100 },
	{ Id = "golden", Name = "Goldene Zitronen", Emoji = "✨", Description = "+2 % Chance auf 10× Verkauf", BaseCost = 40, Growth = 4, Max = 5, Value = 0.02 },
	{ Id = "discount", Name = "Schnäppchenjäger", Emoji = "🏷️", Description = "Level kosten 8 % weniger", BaseCost = 30, Growth = 4, Max = 5, Value = 0.08 },
	{ Id = "school", Name = "Manager-Schule", Emoji = "🎓", Description = "Manager & Maschinen 25 % billiger", BaseCost = 20, Growth = 5, Max = 3, Value = 0.25 },
	{ Id = "night", Name = "Nachtschicht", Emoji = "🌙", Description = "+15 % Offline-Geld und +2 h", BaseCost = 15, Growth = 3, Max = 5, Value = 0.15 },
	{ Id = "charisma", Name = "Alien-Charisma", Emoji = "👽", Description = "Jeder Investor +0,5 % mehr", BaseCost = 100, Growth = 5, Max = 6, Value = 0.005 },
}
Config.PowerById = {}
for _, p in ipairs(Config.Powers) do
	Config.PowerById[p.Id] = p
end

--------------------------------------------------------------------------
-- Frucht-Evolution (Void-Portal). Setzt sogar die Investoren zurück,
-- gibt aber für immer viel mehr Geld und Tempo.
--------------------------------------------------------------------------
Config.Evolution = {
	BaseRequirement = 5000, -- Investoren insgesamt (behalten + ausgegeben + nächster Rebirth)
	Growth = 100,
	IncomeMult = 5,
	SpeedMult = 2,
}

--------------------------------------------------------------------------
-- Offline-Geld, tägliche Belohnung, Geheimnisse
--------------------------------------------------------------------------
Config.Offline = { BaseRate = 0.25, BaseHours = 4, HoursPerLevel = 2, MinSeconds = 60 }

Config.Daily = {
	Minutes = { 5, 10, 15, 20, 30, 45, 60 }, -- so viele Minuten Einnahmen gibt es an Tag 1..7
	MinReward = 100,
}

Config.Secrets = {
	UfoKeyInvestorMult = 1.5, -- UFO-Schlüssel zu Zorp bringen = Investoren 50 % stärker
	ObbyRewardMinutes = 10,
	ObbyRewardMin = 500,
	ObbyCooldown = 20 * 3600,
	LeverColors = { "Rot", "Blau", "Grün", "Gelb" },
}

--------------------------------------------------------------------------
-- Server-Events
--------------------------------------------------------------------------
Config.Events = {
	MinInterval = 360,
	MaxInterval = 540,
	List = {
		{ Id = "turbo", Name = "TURBO-ZEIT", Emoji = "⚡", Description = "Alle Förderbänder laufen doppelt so schnell!", Duration = 120, Speed = 2 },
		{ Id = "money", Name = "GELDREGEN", Emoji = "💸", Description = "Alle Einnahmen ×3!", Duration = 90, Income = 3 },
		{ Id = "lemons", Name = "ZITRONEN-REGEN", Emoji = "🍋", Description = "Sammle die goldenen Zitronen ein!", Duration = 60, Pickups = true },
	},
	PickupsPerPlot = 6,
	PickupsLobby = 12,
	PickupSeconds = 20, -- eine goldene Zitrone = 20 Sekunden Einnahmen
	PickupMin = 100,
}

--------------------------------------------------------------------------
-- Gamepässe & Dev-Produkte. 0 = ausgeschaltet. Trage hier deine IDs ein!
--------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCash = { Id = 0, Name = "2× Geld", Emoji = "💰", Description = "Für immer doppeltes Geld" },
	Turbo = { Id = 0, Name = "Turbo-Pass", Emoji = "⚡", Description = "Alle Bänder 1,5× schneller" },
}
Config.DevProducts = {
	SmallCash = { Id = 0, Name = "Geldkoffer", Emoji = "💼", Minutes = 30, Description = "30 Minuten Einnahmen sofort" },
	BigCash = { Id = 0, Name = "Geldtresor", Emoji = "🏦", Minutes = 240, Description = "4 Stunden Einnahmen sofort" },
}

--------------------------------------------------------------------------
-- Sounds (eingebaute Roblox-Sounds). Du kannst sie durch IDs aus dem
-- Creator Store ersetzen, z. B. "rbxassetid://1234567".
--------------------------------------------------------------------------
Config.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Error = "rbxasset://sounds/button.wav",
	Sell = "rbxasset://sounds/clickfast.wav",
	Golden = "rbxasset://sounds/electronicpingshort.wav",
	Whoosh = "rbxasset://sounds/swoosh.wav",
	Rebirth = "rbxasset://sounds/swoosh.wav",
	Lever = "rbxasset://sounds/snap.wav",
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	Music = "", -- z. B. "rbxassetid://..." für Hintergrundmusik
}

--------------------------------------------------------------------------
-- Karte (in Studs). Lokale Koordinaten einer Fabrik: -Z zeigt zum Platz.
--------------------------------------------------------------------------
Config.Layout = {
	PlotSize = 190,
	PlotRadius = 290,
	PlazaRadius = 125,
	IslandRadius = 470,
	LaneSpacing = 30,
	LaneFirstX = -75,
	BeltY = 3, -- Oberkante Förderband
	BeltStartZ = 60,
	BeltEndZ = -40,
	SellerZ = -47,
	MachineZ = 70,
	UpgraderZ = { 36, 12, -12 },
	PanelOffset = Vector3.new(9, 0, 50),
	ManagerPadOffset = Vector3.new(-9, 0, 52),
	UpgraderPadX = -9,
	UnlockPadZ = -58,
	DecorPadPos = Vector3.new(-28, 0, -76),
	SpawnPos = Vector3.new(0, 0, -82),
	SewerOrigin = Vector3.new(0, -260, 0),
}

function Config.LaneX(index: number): number
	return Config.Layout.LaneFirstX + (index - 1) * Config.Layout.LaneSpacing
end

-- Admin-/Test-Menü (nur in Roblox Studio oder für den Spiel-Ersteller sichtbar)
Config.AdminUserIds = {} -- z. B. { 12345678 }

return Config
