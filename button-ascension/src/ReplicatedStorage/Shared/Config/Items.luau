--[[
	Items (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Items
	Depends on: Config/Rarities, Config/Chests, Config/GameConfig

	Every collectible in the game. Each item belongs to one crate pool and
	grants an equip bonus to one stat. Derived values (Bonus, SellValue) are
	computed below from the rarity and crate tier so balance stays centralised.

	Variants: every item also exists as a Golden and a Rainbow version with its
	own id ("<id>:golden", "<id>:rainbow") in Items.ById, so inventory,
	equipping and stats treat them like any other item. Items.List, the
	pools and Items.Count contain base items only (the collection book counts
	base items). Three copies fuse into the next variant; a variant sells for
	exactly as much as the copies it was made from, so fusing never makes Gems.

	Stat keys: sparks, click, luck, crit, passive, xp, gems, golden
	(see GameConfig.ItemStats for how they map onto player stats).
]]

local Rarities = require(script.Parent.Rarities)
local Chests = require(script.Parent.Chests)
local GameConfig = require(script.Parent.GameConfig)

export type Item = {
	Id: string,
	Name: string,
	Icon: string,
	Rarity: string,
	Chest: string,
	Stat: string,
	Description: string,
	-- derived
	Order: number,
	RarityIndex: number,
	Bonus: number,
	SellValue: number,
	-- variants only
	Base: string?, -- id of the normal item
	Variant: string?, -- "golden" | "rainbow"
}

export type VariantDef = {
	Id: string,
	Name: string,
	Level: number,
	Power: number, -- equip power vs. the normal item
	Sell: number, -- sell value vs. the normal item (= copies used to fuse it)
	DropChance: number, -- chance per normal crate roll
	Color: Color3,
}

local Items = {}

-- stylua: ignore
local LIST = {
	-- Spark Crate (starter) -------------------------------------------------------
	{ "paper_clip",      "Paper Clip",         "📎", "Common",    "starter", "click",   "Holds your very first presses together." },
	{ "rusty_bolt",      "Rusty Bolt",         "🔩", "Common",    "starter", "sparks",  "Squeaks with untapped potential." },
	{ "aa_battery",      "AA Battery",         "🔋", "Common",    "starter", "passive", "Slowly leaks energy into your wallet." },
	{ "light_bulb",      "Light Bulb",         "💡", "Uncommon",  "starter", "xp",      "A bright idea, every single time." },
	{ "pocket_magnet",   "Pocket Magnet",      "🧲", "Uncommon",  "starter", "luck",    "Attracts lucky drops like iron filings." },
	{ "spare_cog",       "Spare Cog",          "⚙️", "Rare",      "starter", "click",   "Part of a much bigger machine." },
	{ "floppy_disk",     "Floppy Disk",        "💾", "Rare",      "starter", "gems",    "Contains 1.44 MB of shiny data." },
	{ "arcade_stick",    "Arcade Stick",       "🕹️", "Epic",      "starter", "crit",    "Frame-perfect inputs, frame-perfect crits." },
	{ "golden_plug",     "Golden Plug",        "🔌", "Legendary", "starter", "sparks",  "Plugged straight into the grid." },
	{ "storm_jar",       "Storm in a Jar",     "🌩️", "Mythic",    "starter", "golden",  "A thunderstorm, politely contained." },
	{ "first_button",    "The First Button",   "🔴", "Secret",    "starter", "sparks",  "Where it all began. It still clicks." },
	{ "button_zero",     "Button Zero",        "🟥", "Secret",    "starter", "click",   "The prototype every other button was copied from." },

	-- Neon Crate ---------------------------------------------------------------------
	{ "headphones",      "Bass Headphones",    "🎧", "Common",    "neon", "xp",      "Bass-boosted focus." },
	{ "retro_radio",     "Retro Radio",        "📻", "Common",    "neon", "passive", "Broadcasting Sparks on every frequency." },
	{ "lucky_die",       "Lucky Die",          "🎲", "Common",    "neon", "luck",    "Always rolls just a little higher." },
	{ "puzzle_piece",    "Puzzle Piece",       "🧩", "Uncommon",  "neon", "click",   "Fits perfectly into any combo." },
	{ "neon_disc",       "Neon Disc",          "💿", "Uncommon",  "neon", "sparks",  "Spinning at 45 RPM forever." },
	{ "bullseye",        "Bullseye",           "🎯", "Rare",      "neon", "crit",    "Never misses the sweet spot." },
	{ "game_pad",        "Game Pad",           "🎮", "Rare",      "neon", "click",   "Press A to profit." },
	{ "space_invader",   "Space Invader",      "👾", "Epic",      "neon", "gems",    "Came for the Gems, stayed for the presses." },
	{ "pixel_crown",     "Pixel Crown",        "👑", "Legendary", "neon", "sparks",  "Rule the high-score table." },
	{ "neon_dragon",     "Neon Dragon",        "🐉", "Mythic",    "neon", "luck",    "Breathes pure, glowing luck." },
	{ "glitch",          "The Glitch",         "🌀", "Secret",    "neon", "golden",  "ERR_BUTTON_OVERFLOW." },
	{ "neon_cat",        "Neon Cat",           "🐈", "Secret",    "neon", "luck",    "Always lands on its feet. Usually on a Secret." },

	-- Plasma Crate -------------------------------------------------------------------
	{ "test_tube",       "Test Tube",          "🧪", "Common",    "plasma", "xp",      "Bubbling with experimental knowledge." },
	{ "microscope",      "Microscope",         "🔬", "Common",    "plasma", "luck",    "Spots lucky atoms others miss." },
	{ "petri_dish",      "Petri Dish",         "🧫", "Common",    "plasma", "passive", "Something in here is growing Sparks." },
	{ "dna_helix",       "DNA Helix",          "🧬", "Uncommon",  "plasma", "xp",      "Engineered for faster learning." },
	{ "plasma_orb",      "Plasma Orb",         "🔮", "Uncommon",  "plasma", "sparks",  "Crackles when you get close." },
	{ "fire_core",       "Fire Core",          "🔥", "Rare",      "plasma", "click",   "Every press leaves scorch marks." },
	{ "frost_core",      "Frost Core",         "❄️", "Rare",      "plasma", "crit",    "Cold, calculated, critical." },
	{ "lab_robot",       "Lab Robot",          "🤖", "Epic",      "plasma", "passive", "Presses buttons while you sleep." },
	{ "atomic_heart",    "Atomic Heart",       "⚛️", "Legendary", "plasma", "sparks",  "Splits atoms, multiplies Sparks." },
	{ "plasma_eagle",    "Plasma Eagle",       "🦅", "Mythic",    "plasma", "golden",  "Soars over golden opportunities." },
	{ "mad_button",      "The Mad Button",     "🧠", "Secret",    "plasma", "click",   "Do NOT press. (They pressed.)" },
	{ "golden_alembic",  "Golden Alembic",     "⚗️", "Secret",    "plasma", "golden",  "Distils golden presses out of thin air." },

	-- Void Crate ---------------------------------------------------------------------
	{ "void_pebble",     "Void Pebble",        "🌑", "Common",    "void", "sparks",  "Heavier than it looks." },
	{ "shadow_mask",     "Shadow Mask",        "🎭", "Common",    "void", "crit",    "Strikes from the dark." },
	{ "hourglass_void",  "Leaking Hourglass",  "⌛", "Common",    "void", "passive", "Time drips out as Sparks." },
	{ "ghost_spark",     "Ghost Spark",        "👻", "Uncommon",  "void", "luck",    "Haunts crates until they pay out." },
	{ "dark_matter",     "Dark Matter",        "🌌", "Uncommon",  "void", "xp",      "Nobody knows what it is. It helps." },
	{ "void_eye",        "Void Eye",           "🧿", "Rare",      "void", "gems",    "Stares back. Finds Gems." },
	{ "skull_relay",     "Skull Relay",        "💀", "Rare",      "void", "click",   "Dead serious about pressing." },
	{ "comet_shard",     "Comet Shard",        "☄️", "Epic",      "void", "crit",    "Burning at impact velocity." },
	{ "abyss_key",       "Abyss Key",          "🗝️", "Legendary", "void", "luck",    "Unlocks crates you did not know existed." },
	{ "eclipse",         "Eclipse",            "🌘", "Mythic",    "void", "sparks",  "When the light goes out, Sparks pour in." },
	{ "null_button",     "The Null Button",    "⚫", "Secret",    "void", "sparks",  "Pressing it presses everything." },
	{ "pocket_hole",     "Pocket Black Hole",  "🕳️", "Secret",    "void", "gems",    "Everything falls in. Gems come out." },

	-- Celestial Crate ----------------------------------------------------------------
	{ "stardust",        "Stardust",           "✨", "Common",    "celestial", "sparks",  "Collected one twinkle at a time." },
	{ "moonstone",       "Moonstone",          "🌙", "Common",    "celestial", "xp",      "Glows brighter as you learn." },
	{ "star_compass",    "Star Compass",       "🧭", "Common",    "celestial", "luck",    "Always points toward treasure." },
	{ "shooting_star",   "Shooting Star",      "🌠", "Uncommon",  "celestial", "click",   "Make a wish. Then press." },
	{ "satellite",       "Satellite",          "🛰️", "Uncommon",  "celestial", "passive", "Beams Sparks down from orbit." },
	{ "telescope",       "Telescope",          "🔭", "Rare",      "celestial", "luck",    "Sees Legendary drops light-years away." },
	{ "sun_shard",       "Sun Shard",          "☀️", "Rare",      "celestial", "sparks",  "A sliver of a star." },
	{ "ufo",             "Lost UFO",           "🛸", "Epic",      "celestial", "gems",    "Abducts Gems from other dimensions." },
	{ "galaxy_heart",    "Galaxy Heart",       "💫", "Legendary", "celestial", "click",   "Beats once per press." },
	{ "star_unicorn",    "Star Unicorn",       "🦄", "Mythic",    "celestial", "luck",    "Mythical, therefore lucky." },
	{ "star_button",     "The Star Button",    "⭐", "Secret",    "celestial", "golden",  "Pressed by constellations." },
	{ "cosmic_whale",    "Cosmic Whale",       "🐋", "Secret",    "celestial", "passive", "Swims between stars, humming in Sparks." },

	-- Singularity Core ---------------------------------------------------------------
	{ "hourglass",       "Golden Hourglass",   "⏳", "Common",    "singularity", "passive", "Time itself pays interest." },
	{ "infinity_loop",   "Infinity Loop",      "♾️", "Common",    "singularity", "sparks",  "Never ends. Never stops paying." },
	{ "quantum_bit",     "Quantum Bit",        "💠", "Common",    "singularity", "luck",    "Both lucky and unlucky until observed." },
	{ "rocket",          "Rocket Booster",     "🚀", "Uncommon",  "singularity", "click",   "Presses at escape velocity." },
	{ "prism_shard",     "Prism Shard",        "🔷", "Uncommon",  "singularity", "gems",    "Refracts presses into Gems." },
	{ "supernova",       "Supernova",          "💥", "Rare",      "singularity", "crit",    "One press. Total annihilation." },
	{ "rainbow_bridge",  "Rainbow Bridge",     "🌈", "Rare",      "singularity", "xp",      "A shortcut to the next level." },
	{ "time_crystal",    "Time Crystal",       "🔶", "Epic",      "singularity", "passive", "Earns tomorrow's Sparks today." },
	{ "singular_crown",  "Singularity Crown",  "🏆", "Legendary", "singularity", "sparks",  "For those who pressed beyond infinity." },
	{ "world_serpent",   "World Serpent",      "🐲", "Mythic",    "singularity", "click",   "Coils around the universe, pressing." },
	{ "final_button",    "The Final Button",   "🔘", "Secret",    "singularity", "sparks",  "There is nothing after this. Or is there?" },
	{ "big_bang",        "The Big Bang",       "🎆", "Secret",    "singularity", "click",   "Pressed once. Everything else followed." },

	-- Prism Cache (Gems) --------------------------------------------------------------
	{ "prism_lens",      "Prism Lens",         "🔍", "Rare",      "prism", "luck",    "Splits light into pure luck." },
	{ "gem_core",        "Gem Core",           "💎", "Rare",      "prism", "gems",    "The heart of every Gem." },
	{ "fortune_clover",  "Fortune Clover",     "🍀", "Epic",      "prism", "luck",    "Four leaves, infinite luck." },
	{ "treasure_key",    "Treasure Key",       "🔑", "Epic",      "prism", "golden",  "Opens golden opportunities." },
	{ "royal_shield",    "Royal Shield",       "🛡️", "Legendary", "prism", "crit",    "Deflects anything that is not a crit." },
	{ "crystal_sword",   "Crystal Sword",      "⚔️", "Legendary", "prism", "click",   "Cuts through any price tag." },
	{ "prism_heart",     "Prismatic Heart",    "💖", "Mythic",    "prism", "sparks",  "Loves you back in Sparks." },
	{ "sage_button",     "The Sage Button",    "🌟", "Secret",    "prism", "xp",      "Knows every press you will ever make." },
	{ "prism_peacock",   "Prism Peacock",      "🦚", "Secret",    "prism", "gems",    "Fans out every colour of the Gem spectrum." },
}

Items.List = {} :: { Item }
Items.ById = {} :: { [string]: Item }
-- PoolByChest[chestId][rarityId] = { itemId, ... }
Items.PoolByChest = {} :: { [string]: { [string]: { string } } }
Items.Count = 0

for index, row in ipairs(LIST) do
	local id, name, icon, rarityId, chestId, stat, description = table.unpack(row)
	local rarity = Rarities.ById[rarityId]
	local chest = Chests.ById[chestId]
	local statDef = GameConfig.ItemStats[stat]
	assert(rarity, "Unknown rarity for item " .. id)
	assert(chest, "Unknown chest for item " .. id)
	assert(statDef, "Unknown stat for item " .. id)
	assert(Items.ById[id] == nil, "Duplicate item id " .. id)

	local item: Item = {
		Id = id,
		Name = name,
		Icon = icon,
		Rarity = rarityId,
		Chest = chestId,
		Stat = stat,
		Description = description,
		Order = index,
		RarityIndex = rarity.Index,
		Bonus = rarity.Bonus * chest.TierFactor * statDef.Factor,
		SellValue = math.max(1, math.floor(rarity.SellGems * (chest.SellFactor or chest.TierFactor) + 0.5)),
	}
	table.insert(Items.List, item)
	Items.ById[id] = item
	Items.Count += 1

	local pool = Items.PoolByChest[chestId]
	if not pool then
		pool = {}
		Items.PoolByChest[chestId] = pool
	end
	pool[rarityId] = pool[rarityId] or {}
	table.insert(pool[rarityId], id)
end

-- Sanity check: every weighted rarity in every crate must have at least one item.
for _, chest in ipairs(Chests.List) do
	for rarityId, weight in pairs(chest.Weights) do
		if weight > 0 then
			local pool = Items.PoolByChest[chest.Id]
			assert(pool and pool[rarityId] and #pool[rarityId] > 0, `Crate {chest.Id} has no {rarityId} items`)
		end
	end
end

-- Variants ---------------------------------------------------------------------------

-- Copies of one item (and variant) needed to fuse one of the next variant.
Items.FuseCost = 3

Items.Variants = {
	{ Id = "golden", Name = "Golden", Level = 2, Power = 2.5, Sell = 3, DropChance = 0.015, Color = Color3.fromRGB(255, 205, 64) },
	{ Id = "rainbow", Name = "Rainbow", Level = 3, Power = 6, Sell = 9, DropChance = 0.0015, Color = Color3.fromRGB(255, 120, 220) },
} :: { VariantDef }
Items.VariantById = {} :: { [string]: VariantDef }
for _, variant in ipairs(Items.Variants) do
	Items.VariantById[variant.Id] = variant
end

-- Id of an item's variant ("paper_clip", "golden" -> "paper_clip:golden"); nil variant = normal.
function Items.variantId(baseId: string, variant: string?): string
	return if variant then baseId .. ":" .. variant else baseId
end

for _, base in ipairs(table.clone(Items.List)) do
	for _, variant in ipairs(Items.Variants) do
		local id = Items.variantId(base.Id, variant.Id)
		Items.ById[id] = {
			Id = id,
			Name = `{variant.Name} {base.Name}`,
			Icon = base.Icon,
			Rarity = base.Rarity,
			Chest = base.Chest,
			Stat = base.Stat,
			Description = base.Description,
			Order = base.Order,
			RarityIndex = base.RarityIndex,
			Bonus = base.Bonus * variant.Power,
			SellValue = base.SellValue * variant.Sell,
			Base = base.Id,
			Variant = variant.Id,
		}
	end
end

-- The normal item an id belongs to (itself for normal items).
function Items.baseOf(id: string): string
	local item = Items.ById[id]
	return if item and item.Base then item.Base else id
end

-- Variant level: 1 normal, 2 golden, 3 rainbow.
function Items.variantLevel(id: string): number
	local item = Items.ById[id]
	local variant = item and item.Variant and Items.VariantById[item.Variant]
	return if variant then variant.Level else 1
end

-- The id three copies of `id` fuse into, or nil when it is already Rainbow.
function Items.fuseResult(id: string): string?
	local item = Items.ById[id]
	if not item then
		return nil
	end
	local level = Items.variantLevel(id)
	local nextVariant = Items.Variants[level] -- Variants[1] is golden (level 2)
	if not nextVariant then
		return nil
	end
	return Items.variantId(Items.baseOf(id), nextVariant.Id)
end

function Items.get(id: string): Item?
	return Items.ById[id]
end

return Items
