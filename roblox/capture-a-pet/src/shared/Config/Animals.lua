-- Every collectible animal. Models are built from blocks at runtime (see shared/AnimalModel),
-- so adding an animal is just adding a row here. If you put a Model named exactly like the
-- animal's Id into ReplicatedStorage.AnimalModels, that model is used instead.
--
-- Fields:
--   Rarity      1 Common .. 7 Secret (see Config/Game.Rarities)
--   Zone        which zone of the run lane it lives in
--   Income      cash per second at average weight, before multipliers
--   Weight      {min, max} in kg; heavier = more income
--   Look        block-model recipe (colors and body features)

local RARITY_SCALE = { 1, 1.2, 1.45, 1.8, 2.3, 3.0, 3.6 }
local WILD_WEIGHT = { 50, 28, 13, 6, 2.2, 0.6, 0.08 } -- spawn weight per rarity on the lane
local EGG_WEIGHT = { 45, 28, 15, 8, 3, 0.9, 0.12 } -- rarity weights of eggs in guarded nests
local LAIR_EGG_WEIGHT = { 0, 0, 40, 30, 18, 9, 3 } -- rarity weights of eggs in the Dragon Lair event

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local list = {
	-- Zone 1: Sunny Meadow --------------------------------------------------------------
	{ Id = "Bunny", Rarity = 1, Zone = 1, Income = 2, Weight = { 2, 6 },
		Look = { Body = c(245, 245, 245), Accent = c(255, 180, 200), Ears = "long", Tail = "fluffy", Snout = "flat", Legs = "short" } },
	{ Id = "Piglet", Rarity = 1, Zone = 1, Income = 3, Weight = { 10, 30 },
		Look = { Body = c(255, 170, 185), Accent = c(235, 120, 145), Ears = "floppy", Tail = "short", Snout = "pig", Legs = "short" } },
	{ Id = "Lamb", Rarity = 2, Zone = 1, Income = 7, Weight = { 20, 45 },
		Look = { Body = c(250, 250, 240), Accent = c(60, 50, 50), Ears = "floppy", Tail = "short", Snout = "short", Fluffy = true } },
	{ Id = "Fox", Rarity = 2, Zone = 1, Income = 9, Weight = { 6, 14 },
		Look = { Body = c(240, 130, 40), Accent = c(255, 255, 255), Ears = "pointy", Tail = "fluffy", Snout = "long" } },
	{ Id = "Brown Bear", Rarity = 3, Zone = 1, Income = 22, Weight = { 180, 360 },
		Look = { Body = c(120, 80, 50), Accent = c(170, 125, 85), Ears = "round", Tail = "short", Snout = "short", Bulky = true } },
	{ Id = "Panda", Rarity = 3, Zone = 1, Income = 26, Weight = { 90, 160 },
		Look = { Body = c(250, 250, 250), Accent = c(25, 25, 25), Ears = "round", Tail = "short", Snout = "short", Bulky = true, Panda = true } },
	{ Id = "Deer", Rarity = 4, Zone = 1, Income = 60, Weight = { 60, 120 },
		Look = { Body = c(185, 125, 75), Accent = c(250, 240, 220), Ears = "pointy", Horns = "antlers", Tail = "short", Snout = "long", Legs = "long", Spots = true } },
	{ Id = "Gray Wolf", Rarity = 4, Zone = 1, Income = 70, Weight = { 35, 70 },
		Look = { Body = c(130, 135, 145), Accent = c(220, 220, 225), Ears = "pointy", Tail = "fluffy", Snout = "long" } },
	{ Id = "Golden Stag", Rarity = 5, Zone = 1, Income = 160, Weight = { 120, 220 },
		Look = { Body = c(255, 200, 60), Accent = c(255, 245, 200), Ears = "pointy", Horns = "antlers", Tail = "short", Snout = "long", Legs = "long", Shiny = true } },
	{ Id = "Meadow Unicorn", Rarity = 6, Zone = 1, Income = 420, Weight = { 300, 500 },
		Look = { Body = c(255, 240, 255), Accent = c(255, 140, 230), Ears = "pointy", Horns = "unicorn", Tail = "long", Snout = "long", Legs = "long", Mane = true, Sparkle = true } },

	-- Zone 2: Red Canyon ----------------------------------------------------------------
	{ Id = "Camel", Rarity = 1, Zone = 2, Income = 900, Weight = { 300, 600 },
		Look = { Body = c(215, 170, 110), Accent = c(180, 135, 80), Ears = "round", Tail = "short", Snout = "long", Legs = "long", Hump = true, LongNeck = true } },
	{ Id = "Coyote", Rarity = 1, Zone = 2, Income = 1200, Weight = { 9, 20 },
		Look = { Body = c(190, 150, 100), Accent = c(240, 225, 200), Ears = "pointy", Tail = "fluffy", Snout = "long" } },
	{ Id = "Meerkat", Rarity = 2, Zone = 2, Income = 2600, Weight = { 1, 2 },
		Look = { Body = c(200, 165, 120), Accent = c(90, 60, 40), Ears = "round", Tail = "long", Snout = "short", Legs = "short" } },
	{ Id = "Lion", Rarity = 2, Zone = 2, Income = 3500, Weight = { 150, 250 },
		Look = { Body = c(230, 175, 80), Accent = c(150, 80, 30), Ears = "round", Tail = "long", Snout = "short", Mane = true } },
	{ Id = "Rhino", Rarity = 3, Zone = 2, Income = 9000, Weight = { 1800, 2500 },
		Look = { Body = c(150, 150, 155), Accent = c(230, 225, 210), Ears = "round", Horns = "rhino", Tail = "short", Snout = "short", Bulky = true } },
	{ Id = "Hyena", Rarity = 3, Zone = 2, Income = 11000, Weight = { 40, 80 },
		Look = { Body = c(200, 170, 120), Accent = c(70, 50, 40), Ears = "round", Tail = "short", Snout = "long", Spots = true } },
	{ Id = "Sand Tiger", Rarity = 4, Zone = 2, Income = 30000, Weight = { 180, 300 },
		Look = { Body = c(240, 200, 130), Accent = c(130, 70, 30), Ears = "round", Tail = "long", Snout = "short", Stripes = true } },
	{ Id = "Desert Dragon", Rarity = 5, Zone = 2, Income = 90000, Weight = { 2000, 4000 },
		Look = { Body = c(210, 120, 50), Accent = c(255, 210, 120), Ears = "none", Horns = "small", Tail = "spiked", Snout = "long", Wings = true } },
	{ Id = "Sphinx Cat", Rarity = 6, Zone = 2, Income = 260000, Weight = { 500, 900 },
		Look = { Body = c(245, 215, 140), Accent = c(60, 120, 220), Ears = "pointy", Tail = "long", Snout = "short", Shiny = true, Sparkle = true } },
	{ Id = "Bone Dragon", Rarity = 7, Zone = 2, Income = 900000, Weight = { 6000, 12000 },
		Look = { Body = c(225, 220, 240), Accent = c(150, 140, 190), Eye = c(150, 255, 255), Ears = "none", Horns = "small", Tail = "spiked", Snout = "long", Wings = true, Skeleton = true, LongNeck = true } },

	-- Zone 3: Frost Peaks ---------------------------------------------------------------
	{ Id = "Arctic Fox", Rarity = 1, Zone = 3, Income = 6e5, Weight = { 3, 8 },
		Look = { Body = c(250, 252, 255), Accent = c(180, 210, 240), Ears = "pointy", Tail = "fluffy", Snout = "long" } },
	{ Id = "Husky", Rarity = 1, Zone = 3, Income = 8e5, Weight = { 20, 30 },
		Look = { Body = c(110, 115, 130), Accent = c(250, 250, 255), Eye = c(80, 180, 255), Ears = "pointy", Tail = "fluffy", Snout = "long" } },
	{ Id = "Polar Bear", Rarity = 2, Zone = 3, Income = 1.8e6, Weight = { 350, 700 },
		Look = { Body = c(245, 248, 250), Accent = c(40, 40, 50), Ears = "round", Tail = "short", Snout = "long", Bulky = true } },
	{ Id = "Snow Leopard", Rarity = 2, Zone = 3, Income = 2.4e6, Weight = { 30, 55 },
		Look = { Body = c(230, 230, 225), Accent = c(90, 90, 100), Ears = "round", Tail = "fluffy", Snout = "short", Spots = true } },
	{ Id = "Reindeer", Rarity = 3, Zone = 3, Income = 6e6, Weight = { 90, 180 },
		Look = { Body = c(140, 100, 70), Accent = c(240, 230, 215), Ears = "pointy", Horns = "antlers", Tail = "short", Snout = "long", Legs = "long", RedNose = true } },
	{ Id = "Mammoth", Rarity = 3, Zone = 3, Income = 8e6, Weight = { 5000, 8000 },
		Look = { Body = c(130, 85, 55), Accent = c(245, 240, 225), Ears = "floppy", Horns = "tusks", Tail = "short", Snout = "trunk", Bulky = true, Fluffy = true } },
	{ Id = "Ice Wolf", Rarity = 4, Zone = 3, Income = 2.2e7, Weight = { 60, 110 },
		Look = { Body = c(170, 220, 255), Accent = c(240, 250, 255), Eye = c(40, 120, 255), Ears = "pointy", Tail = "fluffy", Snout = "long", Sparkle = true } },
	{ Id = "Frost Tiger", Rarity = 5, Zone = 3, Income = 7e7, Weight = { 250, 400 },
		Look = { Body = c(235, 245, 255), Accent = c(60, 110, 200), Ears = "round", Tail = "long", Snout = "short", Stripes = true } },
	{ Id = "Crystal Dragon", Rarity = 6, Zone = 3, Income = 2e8, Weight = { 4000, 7000 },
		Look = { Body = c(140, 220, 255), Accent = c(230, 250, 255), Ears = "none", Horns = "small", Tail = "spiked", Snout = "long", Wings = true, Shiny = true, Sparkle = true } },
	{ Id = "Yeti Bear", Rarity = 7, Zone = 3, Income = 7e8, Weight = { 900, 1500 },
		Look = { Body = c(250, 250, 255), Accent = c(110, 170, 230), Ears = "round", Horns = "small", Tail = "short", Snout = "short", Bulky = true, Fluffy = true, Sparkle = true } },

	-- Zone 4: Lava Rift -----------------------------------------------------------------
	{ Id = "Lava Hound", Rarity = 1, Zone = 4, Income = 5e8, Weight = { 40, 70 },
		Look = { Body = c(60, 40, 40), Accent = c(255, 110, 30), Eye = c(255, 200, 0), Ears = "pointy", Tail = "long", Snout = "long", Fire = true } },
	{ Id = "Magma Boar", Rarity = 1, Zone = 4, Income = 7e8, Weight = { 120, 220 },
		Look = { Body = c(80, 50, 45), Accent = c(255, 140, 40), Ears = "floppy", Horns = "tusks", Tail = "short", Snout = "pig", Legs = "short" } },
	{ Id = "Fire Bull", Rarity = 2, Zone = 4, Income = 1.6e9, Weight = { 700, 1100 },
		Look = { Body = c(150, 30, 25), Accent = c(255, 200, 80), Ears = "round", Horns = "bull", Tail = "long", Snout = "short", Bulky = true, Fire = true } },
	{ Id = "Ember Panther", Rarity = 2, Zone = 4, Income = 2.2e9, Weight = { 60, 100 },
		Look = { Body = c(30, 25, 30), Accent = c(255, 120, 20), Eye = c(255, 220, 60), Ears = "round", Tail = "long", Snout = "short" } },
	{ Id = "Obsidian Rhino", Rarity = 3, Zone = 4, Income = 6e9, Weight = { 2500, 3500 },
		Look = { Body = c(35, 30, 45), Accent = c(200, 80, 255), Ears = "round", Horns = "rhino", Tail = "short", Snout = "short", Bulky = true, Shiny = true } },
	{ Id = "Inferno Wolf", Rarity = 4, Zone = 4, Income = 2e10, Weight = { 90, 160 },
		Look = { Body = c(200, 50, 20), Accent = c(255, 210, 60), Ears = "pointy", Tail = "fluffy", Snout = "long", Fire = true } },
	{ Id = "Phoenix Lion", Rarity = 4, Zone = 4, Income = 2.6e10, Weight = { 200, 320 },
		Look = { Body = c(255, 140, 30), Accent = c(255, 60, 20), Ears = "round", Tail = "long", Snout = "short", Mane = true, Wings = true, Fire = true } },
	{ Id = "Oni Tiger", Rarity = 5, Zone = 4, Income = 8e10, Weight = { 800, 1400 },
		Look = { Body = c(250, 240, 245), Accent = c(220, 40, 80), Eye = c(255, 40, 60), Ears = "round", Horns = "oni", Tail = "long", Snout = "short", Stripes = true, Bulky = true, Sparkle = true } },
	{ Id = "Volcano Dragon", Rarity = 6, Zone = 4, Income = 2.5e11, Weight = { 8000, 15000 },
		Look = { Body = c(120, 20, 20), Accent = c(255, 160, 30), Eye = c(255, 230, 0), Ears = "none", Horns = "oni", Tail = "spiked", Snout = "long", Wings = true, Fire = true, LongNeck = true } },
	{ Id = "Cosmic Panda", Rarity = 7, Zone = 4, Income = 1e12, Weight = { 1000, 2000 },
		Look = { Body = c(60, 30, 120), Accent = c(255, 120, 255), Eye = c(255, 255, 255), Ears = "round", Tail = "short", Snout = "short", Bulky = true, Panda = true, Sparkle = true, Shiny = true } },
}

local Animals = {
	List = list,
	ById = {},
	ByZone = { {}, {}, {}, {} },
	RarityScale = RARITY_SCALE,
	WildWeight = WILD_WEIGHT,
	EggWeight = EGG_WEIGHT,
	LairEggWeight = LAIR_EGG_WEIGHT,
}

for order, def in ipairs(list) do
	def.Order = order
	def.Scale = RARITY_SCALE[def.Rarity]
	Animals.ById[def.Id] = def
	table.insert(Animals.ByZone[def.Zone], def)
end

-- Weight of a rarity after luck. Luck pushes rarer tiers up more than common ones.
function Animals.luckWeight(baseWeight: number, rarity: number, luck: number): number
	if rarity <= 1 or luck <= 1 then
		return baseWeight
	end
	return baseWeight * luck ^ ((rarity - 1) / 6)
end

-- Odds table {Def, Chance} for wild animals of a zone, used for rolling and for display.
function Animals.odds(zone: number, luck: number)
	local pool = Animals.ByZone[zone]
	-- Weight is split between all animals that share a rarity in this zone.
	local perRarity = {}
	for _, def in ipairs(pool) do
		perRarity[def.Rarity] = (perRarity[def.Rarity] or 0) + 1
	end
	local total = 0
	local rows = {}
	for _, def in ipairs(pool) do
		local w = Animals.luckWeight(WILD_WEIGHT[def.Rarity], def.Rarity, luck) / perRarity[def.Rarity]
		total += w
		table.insert(rows, { Def = def, Weight = w })
	end
	for _, row in ipairs(rows) do
		row.Chance = row.Weight / total
	end
	return rows
end

function Animals.rollWild(zone: number, luck: number, rng: Random)
	local rows = Animals.odds(zone, luck)
	local pick = rng:NextNumber()
	local acc = 0
	for _, row in ipairs(rows) do
		acc += row.Chance
		if pick <= acc then
			return row.Def
		end
	end
	return rows[#rows].Def
end

-- Chance per rarity for eggs, {rarity -> chance}.
function Animals.eggOdds(weights, luck: number)
	local total = 0
	local out = {}
	for rarity, w in ipairs(weights) do
		local lw = Animals.luckWeight(w, rarity, luck)
		out[rarity] = lw
		total += lw
	end
	for rarity, w in ipairs(out) do
		out[rarity] = w / total
	end
	return out
end

function Animals.rollEggRarity(weights, luck: number, rng: Random): number
	local odds = Animals.eggOdds(weights, luck)
	local pick = rng:NextNumber()
	local acc = 0
	for rarity, chance in ipairs(odds) do
		acc += chance
		if pick <= acc then
			return rarity
		end
	end
	return #odds
end

-- A random species of exactly this rarity in the zone; falls back to the closest rarity.
function Animals.pickSpecies(zone: number, rarity: number, rng: Random)
	local pool = Animals.ByZone[math.clamp(zone, 1, #Animals.ByZone)]
	for distance = 0, 6 do
		for _, r in ipairs({ rarity - distance, rarity + distance }) do
			local matches = {}
			for _, def in ipairs(pool) do
				if def.Rarity == r then
					table.insert(matches, def)
				end
			end
			if #matches > 0 then
				return matches[rng:NextInteger(1, #matches)]
			end
		end
	end
	return pool[1]
end

return Animals
