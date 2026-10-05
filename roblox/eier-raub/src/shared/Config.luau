-- Eier-Raub – gemeinsame Einstellungen (Server + Client)
-- Hier kannst du Preise, Eier, Seltenheiten und Admins anpassen.

local Config = {}

---------------------------------------------------------------------
-- Admins
---------------------------------------------------------------------
-- UserIds, die das Admin-Panel öffnen dürfen.
-- Der Besitzer des Spiels (bzw. Gruppen-Besitzer) ist automatisch Admin.
-- In Roblox Studio ist jeder Spieler Admin, damit du testen kannst.
Config.Admins = {
	-- 123456789,
}

---------------------------------------------------------------------
-- Spielregeln
---------------------------------------------------------------------
Config.StartMoney = 100
Config.SlotsPerBase = 10
Config.LockDuration = 60 -- Sekunden, die eine Basis gesperrt bleibt
Config.SpawnInterval = 2.5 -- Sekunden zwischen zwei Eiern auf dem Laufband
Config.ConveyorSpeed = 7 -- Studs pro Sekunde
Config.EggWalkSpeed = 22 -- so schnell läuft ein gekauftes Ei zur Basis
Config.SellFactor = 0.5 -- Verkaufen bringt 50 % des Preises
Config.NormalWalkSpeed = 16
Config.CarryWalkSpeed = 12 -- Diebe sind langsamer
Config.StealHoldTime = 1.5
Config.BatCooldown = 0.9
Config.BatRange = 8
Config.BatKnockback = 55
Config.AutoSaveInterval = 120
Config.DataStoreName = "EierRaub_v1"

Config.EggBaseSize = Vector3.new(2.4, 3.1, 2.4)

---------------------------------------------------------------------
-- Seltenheiten
---------------------------------------------------------------------
Config.Rarities = {
	Gewoehnlich = {
		hatchTime = 10, -- Sekunden bis zum Schlüpfen
		name = "Gewöhnlich",
		order = 1,
		weight = 55,
		scale = 1.0,
		color = Color3.fromRGB(205, 205, 205),
		gradient = nil,
	},
	Selten = {
		hatchTime = 20, -- Sekunden bis zum Schlüpfen
		name = "Selten",
		order = 2,
		weight = 28,
		scale = 1.1,
		color = Color3.fromRGB(80, 170, 255),
	},
	Episch = {
		hatchTime = 40, -- Sekunden bis zum Schlüpfen
		name = "Episch",
		order = 3,
		weight = 12,
		scale = 1.2,
		color = Color3.fromRGB(175, 90, 255),
	},
	Legendaer = {
		hatchTime = 75, -- Sekunden bis zum Schlüpfen
		name = "Legendär",
		order = 4,
		weight = 4,
		scale = 1.35,
		color = Color3.fromRGB(255, 190, 40),
	},
	Mythisch = {
		hatchTime = 120, -- Sekunden bis zum Schlüpfen
		name = "Mythisch",
		order = 5,
		weight = 0.9,
		scale = 1.5,
		color = Color3.fromRGB(255, 70, 90),
		gradient = { Color3.fromRGB(255, 60, 90), Color3.fromRGB(255, 150, 60) },
	},
	Goettlich = {
		hatchTime = 180, -- Sekunden bis zum Schlüpfen
		name = "Göttlich",
		order = 6,
		weight = 0.09,
		scale = 1.7,
		color = Color3.fromRGB(255, 255, 160),
		gradient = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 90) },
	},
	Geheim = {
		hatchTime = 300, -- Sekunden bis zum Schlüpfen
		name = "GEHEIM",
		order = 7,
		weight = 0.01,
		scale = 1.9,
		color = Color3.fromRGB(30, 30, 30),
		gradient = { Color3.fromRGB(20, 20, 20), Color3.fromRGB(140, 0, 255), Color3.fromRGB(20, 20, 20) },
	},
}

-- Reihenfolge für Listen (z. B. im Admin-Panel)
Config.RarityOrder = { "Gewoehnlich", "Selten", "Episch", "Legendaer", "Mythisch", "Goettlich", "Geheim" }

---------------------------------------------------------------------
-- Mutationen (seltene Varianten eines Tiers)
---------------------------------------------------------------------
-- Werden beim SCHLÜPFEN zufällig gewürfelt – eine Überraschung!
Config.Mutations = {
	{ id = "Gold", name = "Gold", chance = 0.06, mult = 2, color = Color3.fromRGB(255, 205, 50) },
	{ id = "Diamant", name = "Diamant", chance = 0.02, mult = 4, color = Color3.fromRGB(110, 235, 255) },
	{ id = "Regenbogen", name = "Regenbogen", chance = 0.005, mult = 10, color = Color3.fromRGB(255, 120, 220) },
}

---------------------------------------------------------------------
-- Eier
---------------------------------------------------------------------
-- price = Kaufpreis, income = Geld pro Sekunde (erst NACH dem Schlüpfen!)
-- creature = Tier, das schlüpft, creatureColor = Farbe des Tiers
local M = Enum.Material
Config.Eggs = {
	{
		id = "wachtel",
		name = "Wachtelei",
		creature = "Wachtelküken",
		creatureColor = Color3.fromRGB(190, 150, 110),
		rarity = "Gewoehnlich",
		price = 25,
		income = 1,
		color = Color3.fromRGB(225, 210, 185),
		material = M.SmoothPlastic,
	},
	{
		id = "huhn",
		name = "Hühnerei",
		creature = "Küken",
		creatureColor = Color3.fromRGB(255, 220, 70),
		rarity = "Gewoehnlich",
		price = 60,
		income = 2,
		color = Color3.fromRGB(245, 240, 230),
		material = M.SmoothPlastic,
	},
	{
		id = "ente",
		name = "Entenei",
		creature = "Entlein",
		creatureColor = Color3.fromRGB(255, 235, 120),
		rarity = "Gewoehnlich",
		price = 120,
		income = 4,
		color = Color3.fromRGB(190, 225, 215),
		material = M.SmoothPlastic,
	},
	{
		id = "schoko",
		name = "Schoko-Ei",
		creature = "Schoko-Häschen",
		creatureColor = Color3.fromRGB(120, 75, 45),
		rarity = "Gewoehnlich",
		price = 200,
		income = 6,
		color = Color3.fromRGB(110, 70, 45),
		material = M.SmoothPlastic,
	},
	{
		id = "gans",
		name = "Gänseei",
		creature = "Gössel",
		creatureColor = Color3.fromRGB(220, 215, 160),
		rarity = "Selten",
		price = 350,
		income = 10,
		color = Color3.fromRGB(240, 235, 200),
		material = M.SmoothPlastic,
	},
	{
		id = "strauss",
		name = "Straußenei",
		creature = "Straußenküken",
		creatureColor = Color3.fromRGB(150, 120, 95),
		rarity = "Selten",
		price = 800,
		income = 21,
		color = Color3.fromRGB(235, 220, 170),
		material = M.Sand,
	},
	{
		id = "pinguin",
		name = "Pinguin-Ei",
		creature = "Pinguinbaby",
		creatureColor = Color3.fromRGB(60, 70, 90),
		rarity = "Selten",
		price = 1600,
		income = 40,
		color = Color3.fromRGB(70, 90, 120),
		material = M.SmoothPlastic,
	},
	{
		id = "kristall",
		name = "Kristall-Ei",
		creature = "Kristallwurm",
		creatureColor = Color3.fromRGB(140, 230, 255),
		rarity = "Episch",
		price = 4000,
		income = 90,
		color = Color3.fromRGB(150, 220, 255),
		material = M.Glass,
	},
	{
		id = "lava",
		name = "Lava-Ei",
		creature = "Lavasalamander",
		creatureColor = Color3.fromRGB(255, 90, 30),
		rarity = "Episch",
		price = 9000,
		income = 190,
		color = Color3.fromRGB(255, 100, 30),
		material = M.CrackedLava,
	},
	{
		id = "frost",
		name = "Frost-Ei",
		creature = "Frostfuchs",
		creatureColor = Color3.fromRGB(225, 245, 255),
		rarity = "Episch",
		price = 18000,
		income = 360,
		color = Color3.fromRGB(200, 240, 255),
		material = M.Ice,
	},
	{
		id = "gold",
		name = "Goldenes Ei",
		creature = "Goldgans",
		creatureColor = Color3.fromRGB(255, 205, 60),
		rarity = "Legendaer",
		price = 50000,
		income = 900,
		color = Color3.fromRGB(255, 200, 40),
		material = M.Foil,
	},
	{
		id = "drache",
		name = "Drachenei",
		creature = "Babydrache",
		creatureColor = Color3.fromRGB(80, 190, 90),
		rarity = "Legendaer",
		price = 120000,
		income = 2000,
		color = Color3.fromRGB(60, 160, 70),
		material = M.Slate,
	},
	{
		id = "galaxie",
		name = "Galaxie-Ei",
		creature = "Sternenwal",
		creatureColor = Color3.fromRGB(110, 60, 230),
		rarity = "Mythisch",
		price = 400000,
		income = 6000,
		color = Color3.fromRGB(90, 40, 200),
		material = M.Neon,
	},
	{
		id = "regenbogen",
		name = "Regenbogen-Ei",
		creature = "Regenbogen-Einhorn",
		creatureColor = Color3.fromRGB(255, 255, 255),
		rarity = "Mythisch",
		price = 1000000,
		income = 14000,
		color = Color3.fromRGB(255, 0, 0),
		material = M.Neon,
		rainbow = true,
	},
	{
		id = "kosmos",
		name = "Kosmisches Ei",
		creature = "Kosmo-Phönix",
		creatureColor = Color3.fromRGB(255, 170, 60),
		rarity = "Goettlich",
		price = 5000000,
		income = 60000,
		color = Color3.fromRGB(255, 250, 200),
		material = M.Neon,
	},
	{
		id = "schatten",
		name = "Schatten-Ei",
		creature = "Schattenkrähe",
		creatureColor = Color3.fromRGB(40, 20, 60),
		rarity = "Geheim",
		price = 25000000,
		income = 250000,
		color = Color3.fromRGB(25, 15, 40),
		material = M.Neon,
	},
}

Config.EggsById = {}
for _, egg in Config.Eggs do
	Config.EggsById[egg.id] = egg
end

---------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------
function Config.getMutation(mutId: string?)
	if not mutId or mutId == "" then
		return nil
	end
	for _, m in Config.Mutations do
		if m.id == mutId then
			return m
		end
	end
	return nil
end

local function mult(mutId)
	local m = Config.getMutation(mutId)
	return m and m.mult or 1
end

function Config.getPrice(id: string, mutId: string?): number
	return math.floor(Config.EggsById[id].price * mult(mutId))
end

function Config.getIncome(id: string, mutId: string?): number
	return math.floor(Config.EggsById[id].income * mult(mutId))
end

-- Name eines Eis (noch nicht geschlüpft)
function Config.getEggName(id: string, mutId: string?): string
	local m = Config.getMutation(mutId)
	local name = Config.EggsById[id].name
	return m and (m.name .. " " .. name) or name
end

-- Name des Tiers, das aus dem Ei schlüpft
function Config.getCreatureName(id: string, mutId: string?): string
	local m = Config.getMutation(mutId)
	local name = Config.EggsById[id].creature
	return m and (m.name .. " " .. name) or name
end

function Config.getDisplayName(id: string, mutId: string?, hatched: boolean?): string
	if hatched then
		return Config.getCreatureName(id, mutId)
	end
	return Config.getEggName(id, mutId)
end

function Config.getHatchTime(id: string): number
	return Config.Rarities[Config.EggsById[id].rarity].hatchTime
end

-- Zufälliges Ei ziehen. luck > 1 macht seltene Eier wahrscheinlicher.
function Config.rollEgg(luck: number?, rng: Random?): string
	local l = luck or 1
	local r = rng or Random.new()
	local counts = {}
	for _, e in Config.Eggs do
		counts[e.rarity] = (counts[e.rarity] or 0) + 1
	end
	local total = 0
	local weights = {}
	for i, e in Config.Eggs do
		local rar = Config.Rarities[e.rarity]
		local w = rar.weight / counts[e.rarity] * l ^ ((rar.order - 1) / 2)
		weights[i] = w
		total += w
	end
	local pick = r:NextNumber() * total
	for i, e in Config.Eggs do
		pick -= weights[i]
		if pick <= 0 then
			return e.id
		end
	end
	return Config.Eggs[1].id
end

-- Überraschungs-Mutation, die beim Schlüpfen gewürfelt wird (oder nil)
function Config.rollMutation(luck: number?, rng: Random?): string?
	local l = luck or 1
	local r = rng or Random.new()
	local roll = r:NextNumber()
	for i = #Config.Mutations, 1, -1 do
		local m = Config.Mutations[i]
		if roll < m.chance * math.sqrt(l) then
			return m.id
		end
	end
	return nil
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
function Config.formatMoney(n: number?): string
	local v = math.floor(n or 0)
	local negative = v < 0
	v = math.abs(v)
	local i = 1
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local text
	if i == 1 then
		text = tostring(v)
	else
		text = string.format("%.1f", v):gsub("%.0$", "") .. SUFFIXES[i]
	end
	return (negative and "-$" or "$") .. text
end

return Config
