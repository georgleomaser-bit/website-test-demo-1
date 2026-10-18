--[[
	Items (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Items
	Depends on: Config/Rarities, Config/Chests, Config/GameConfig

	Every collectible in the game. Each item belongs to one crate pool and
	grants an equip bonus to one stat. Derived values (Bonus, SellValue) are
	computed below from the rarity and crate tier so balance stays centralised.

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

	-- Prism Cache (Gems) --------------------------------------------------------------
	{ "prism_lens",      "Prism Lens",         "🔍", "Rare",      "prism", "luck",    "Splits light into pure luck." },
	{ "gem_core",        "Gem Core",           "💎", "Rare",      "prism", "gems",    "The heart of every Gem." },
	{ "fortune_clover",  "Fortune Clover",     "🍀", "Epic",      "prism", "luck",    "Four leaves, infinite luck." },
	{ "treasure_key",    "Treasure Key",       "🔑", "Epic",      "prism", "golden",  "Opens golden opportunities." },
	{ "royal_shield",    "Royal Shield",       "🛡️", "Legendary", "prism", "crit",    "Deflects anything that is not a crit." },
	{ "crystal_sword",   "Crystal Sword",      "⚔️", "Legendary", "prism", "click",   "Cuts through any price tag." },
	{ "prism_heart",     "Prismatic Heart",    "💖", "Mythic",    "prism", "sparks",  "Loves you back in Sparks." },
	{ "sage_button",     "The Sage Button",    "🌟", "Secret",    "prism", "xp",      "Knows every press you will ever make." },
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
		SellValue = math.max(1, math.floor(rarity.SellGems * chest.TierFactor + 0.5)),
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

function Items.get(id: string): Item?
	return Items.ById[id]
end

return Items
