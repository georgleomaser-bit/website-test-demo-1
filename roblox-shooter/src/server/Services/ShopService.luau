-- =====================================================================
--  CLUTCH CLASH – Währung, Käufe, Kisten, Loadouts, Kosmetik (Server/Services/ShopService)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md C5.9, B18–B21, C9, C12.2.
--
--  GRUNDREGELN
--    * Grant/Spend sind der EINZIGE Weg für Währung und Besitz. Sie yielden nie: erst alles prüfen,
--      dann in einem Rutsch ändern (alles-oder-nichts). Preise kommen nur aus der Server-Config.
--    * Kisten: Random.new() auf dem Server, Quoten aus Config.Shop.Crates.S1 über Shared/Odds
--      (dieselbe Tabelle zeigt der Shop an). Garantie nach 29 Öffnungen ohne Legendary/Mythic.
--    * PolicyService: Gem-Öffnung nur bei RandomAllowed == true (unbekannt = eingeschränkt);
--      Schlüssel-Öffnung (gratis) geht immer.
--
--  Öffentliche API (C5.9):
--    ShopService.Grant(p, grant, reason): boolean            einziger Weg für Währung/Items (kein Yield)
--    ShopService.Spend(p, currency, amount, reason): boolean
--    ShopService.Owns(p, weaponKey): boolean
--    ShopService.OwnsCosmetic(p, id): boolean
--    ShopService.GetLoadout(p, rules?): Types.Loadout        validiert: Besitz, Enabled (Not-Aus), Mutator
--    ShopService.GetCosmetics(p, weaponKey): { Skin, Wrap, Charm }
--    ShopService.Finisher(p): string        ShopService.Tracer(p): string
--    ShopService.TodayFeatured(): { string }
--  Zusätzlich: ShopService.RefreshPlayer(p) (Attribute Vip/Supporter + State, ruft MonetizationService),
--              ShopService.Core (reine Daten-Funktionen für EconomyTests).
--  Request-Aktionen (C9): SetLoadout, SelectPreset, RenamePreset, RandomLoadout, BuyWeapon, BuyItem,
--              OpenCrate, EquipCosmetic, BuyPresetSlot.
--  State-Schlüssel: Coins, Gems, Keys, Shards, Weapons, Loadouts, Cosmetics, Crates, Featured.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Odds = require(Shared:WaitForChild("Odds"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local ShopService = {}
local Services: any = nil

type Reply = Types.Reply
type Loadout = Types.Loadout
type SlotName = Types.SlotName

local SHOP: any = Config.Shop
local COSMETICS: any = Config.Cosmetics

local CURRENCIES: { [string]: boolean } = { Coins = true, Gems = true, Keys = true, Shards = true }
local CURRENCY_ORDER: { Types.Currency } = { "Coins", "Gems", "Keys", "Shards" }
local SLOTS: { SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local SLOT_FIELD: { [string]: string } = { Primary = "P", Secondary = "S", Melee = "M", Utility = "U" }
local FALLBACK_LOADOUT: Loadout =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }
local EQUIP_KINDS: { [string]: boolean } =
	{ Skin = true, Wrap = true, Charm = true, Finisher = true, Tracer = true, Title = true }
local PER_WEAPON_KINDS: { [string]: boolean } = { Skin = true, Wrap = true, Charm = true }

local MAX_BALANCE = math.max(1, tonumber(SHOP.MaxBalance) or 1e9)
local MAX_ID_LEN = 64
local MAX_GRANT_LIST = 256 -- reicht für "alles freischalten" (Admin) und bleibt begrenzt
local MAX_BOOST_SECONDS = math.max(0, tonumber(SHOP.XpBoostCapSeconds) or 86400)
local PRESET_NAME_MAX = math.max(1, tonumber(SHOP.Presets and SHOP.Presets.NameMax) or 16)
local PRESETS_BASE = math.max(1, tonumber(SHOP.Presets and SHOP.Presets.Base) or 3)
local PRESETS_PLUS = math.max(PRESETS_BASE, tonumber(SHOP.Presets and SHOP.Presets.LoadoutPlus) or 8)
local COIN_SLOTS_MAX = math.max(0, tonumber(SHOP.Presets and SHOP.Presets.CoinSlotsMax) or 2)
local PRESET_SLOT_COINS = math.max(1, tonumber(SHOP.PresetSlotCoins) or 5000)
local FEATURED_CHECK_HZ = 1 / 30 -- alle 30 s prüfen, ob ein neuer UTC-Tag begonnen hat

local rng = Random.new() -- Kisten-Zufall: nur Server (C12.5)
local busy: { [Player]: boolean } = {}
local featuredCache: { Day: number, Season: number, Ids: { string } }? = nil

-- =====================================================================
-- 1) KLEINE HELFER
-- =====================================================================
local function service(name: string): any
	return Services and Services[name]
end

-- optionaler Dienst über pcall: (ok, ergebnis)
local function try(name: string, fnName: string, ...: any): (boolean, any)
	local s = service(name)
	if s == nil or type(s[fnName]) ~= "function" then
		return false, nil
	end
	return pcall(s[fnName], ...)
end

local function dataOf(p: Player): any
	local dataService = service("DataService")
	if dataService == nil then
		return nil
	end
	return dataService.Get(p)
end

local function langOf(p: Player): Types.Lang
	local ok, lang = try("PlayerStateService", "LangOf", p)
	return if ok and (lang == "de" or lang == "en") then lang else "en"
end

local function text(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function fail(p: Player, key: string, ...: any): Reply
	return { Ok = false, Message = text(p, key, ...) }
end

local function markDirty(p: Player, ...: string)
	local s = service("PlayerStateService")
	if s and type(s.MarkDirty) == "function" then
		s.MarkDirty(p, ...)
	end
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = try("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function isInteger(n: any): boolean
	return Util.IsFinite(n) and (n :: number) % 1 == 0
end

local function validId(id: any): boolean
	return type(id) == "string" and #id > 0 and #id <= MAX_ID_LEN
end

local function weaponDef(key: any): Types.WeaponDef?
	if not validId(key) then
		return nil
	end
	local def = Config.Weapon(key)
	if def == nil or def.AdminOnly == true then
		return nil -- Admin-Waffen gibt es nie im Shop/Loadout (B11.7)
	end
	return def
end

local function currentSeasonId(): number
	local ok, season = try("ProgressionService", "Season")
	if ok and type(season) == "table" and isInteger(season.Id) then
		return season.Id
	end
	local seasons = Config.Season and Config.Season.Seasons
	return SHOP.SeasonIdAt(seasons, os.time())
end

local function rarityName(rarity: any): string
	return if type(rarity) == "string" then string.upper(rarity) else "?"
end

-- =====================================================================
-- 2) CORE – reine Daten-Funktionen (kein Spieler, kein Yield) -> EconomyTests
-- =====================================================================
local Core = {}
ShopService.Core = Core

-- fehlende Unter-Tabellen anlegen (DataService reconciliert schon; doppelt hält besser)
function Core.Ensure(data: any)
	for _, currency in ipairs(CURRENCY_ORDER) do
		if not isInteger(data[currency]) or data[currency] < 0 then
			data[currency] = 0
		end
	end
	if not isInteger(data.FreeWeaponPicks) or data.FreeWeaponPicks < 0 then
		data.FreeWeaponPicks = 0
	end
	if type(data.Weapons) ~= "table" then
		data.Weapons = {}
	end
	if type(data.Weapons.Owned) ~= "table" then
		data.Weapons.Owned = {}
	end
	if type(data.Cosmetics) ~= "table" then
		data.Cosmetics = {}
	end
	local cos = data.Cosmetics
	if type(cos.Owned) ~= "table" then
		cos.Owned = {}
	end
	if type(cos.Equipped) ~= "table" then
		cos.Equipped = {}
	end
	if type(cos.Equipped.Finisher) ~= "string" then
		cos.Equipped.Finisher = COSMETICS.Defaults.Finisher
	end
	if type(cos.Equipped.Tracer) ~= "string" then
		cos.Equipped.Tracer = COSMETICS.Defaults.Tracer
	end
	if type(cos.Equipped.Title) ~= "string" then
		cos.Equipped.Title = ""
	end
	if type(cos.PerWeapon) ~= "table" then
		cos.PerWeapon = {}
	end
	if type(data.Crates) ~= "table" then
		data.Crates = {}
	end
	if not isInteger(data.Crates.Pity) or data.Crates.Pity < 0 then
		data.Crates.Pity = 0
	end
	if not isInteger(data.Crates.Opened) or data.Crates.Opened < 0 then
		data.Crates.Opened = 0
	end
	if type(data.Boosts) ~= "table" then
		data.Boosts = {}
	end
	if not Util.IsFinite(data.Boosts.XP2Until) then
		data.Boosts.XP2Until = 0
	end
	if type(data.Loadouts) ~= "table" then
		data.Loadouts = {}
	end
	local lo = data.Loadouts
	if type(lo.Presets) ~= "table" then
		lo.Presets = {}
	end
	if not isInteger(lo.Slots) then
		lo.Slots = PRESETS_BASE
	end
	lo.Slots = math.clamp(lo.Slots, PRESETS_BASE, PRESETS_BASE + COIN_SLOTS_MAX)
	if not isInteger(lo.Active) then
		lo.Active = 1
	end
	if type(data.Purchases) ~= "table" then
		data.Purchases = {}
	end
end

function Core.Balance(data: any, currency: string): number
	local value = data and data[currency]
	return if isInteger(value) then value else 0
end

-- Abziehen nur, wenn genug da ist (Prüfen und Abziehen ohne Yield dazwischen)
function Core.Spend(data: any, currency: string, amount: number): boolean
	if not CURRENCIES[currency] or not isInteger(amount) or amount <= 0 then
		return false
	end
	local balance = Core.Balance(data, currency)
	if balance < amount then
		return false
	end
	data[currency] = balance - amount
	return true
end

-- Grant prüfen, OHNE etwas zu ändern. Gibt (ok, Fehlertext) zurück.
function Core.ValidateGrant(data: any, grant: any): (boolean, string?)
	if type(grant) ~= "table" then
		return false, "Grant ist keine Tabelle"
	end
	local fields = SHOP.GrantFields
	for field, value in pairs(grant) do
		local expected = fields[field]
		if expected == nil then
			return false, "unbekanntes Feld " .. tostring(field)
		end
		if type(value) ~= expected then
			return false, ("%s: %s erwartet"):format(tostring(field), expected)
		end
		if expected == "number" then
			if not isInteger(value) then
				return false, tostring(field) .. ": ganze Zahl erwartet"
			end
			if field ~= "FreeWeaponPicks" and value < 0 then
				return false, tostring(field) .. ": darf nicht negativ sein"
			end
		end
	end
	-- Gratis-Waffen-Wahl einlösen: FreeWeaponPicks = -1 zusammen mit der gewählten Waffe
	local picks = grant.FreeWeaponPicks
	if picks ~= nil and picks < 0 then
		if Core.Balance(data, "FreeWeaponPicks") + picks < 0 then
			return false, "keine Gratis-Waffen-Wahl übrig"
		end
		local anyNew = false
		for _, key in ipairs(grant.Weapons or {}) do
			local def = Config.Weapon(key)
			if def and not def.Free and data.Weapons.Owned[key] ~= true then
				anyNew = true
			end
		end
		if not anyNew then
			return false, "Gratis-Wahl nur für eine neue Waffe"
		end
	end
	if grant.Weapons ~= nil then
		if #grant.Weapons > MAX_GRANT_LIST then
			return false, "zu viele Waffen"
		end
		for _, key in ipairs(grant.Weapons) do
			if weaponDef(key) == nil then
				return false, "unbekannte Waffe " .. tostring(key)
			end
		end
	end
	if grant.Cosmetics ~= nil then
		if #grant.Cosmetics > MAX_GRANT_LIST then
			return false, "zu viele Kosmetik-Items"
		end
		for _, id in ipairs(grant.Cosmetics) do
			if not validId(id) or COSMETICS.ById[id] == nil then
				return false, "unbekannte Kosmetik " .. tostring(id)
			end
		end
	end
	return true, nil
end

local function addCurrency(data: any, currency: string, amount: number): number
	local before = Core.Balance(data, currency)
	local after = math.clamp(before + amount, 0, MAX_BALANCE)
	data[currency] = after
	return after - before
end

-- Lokale Teile eines GEPRÜFTEN Grants anwenden (Pass-Teile macht ShopService.Grant vorher).
-- extraGems: Gems aus Pass-Ersatz (Premium schon aktiv / Stufen über dem Maximum).
-- Gibt { geänderte State-Schlüssel } und { Währung = gutgeschrieben } zurück.
function Core.ApplyGrant(data: any, grant: any, now: number, extraGems: number?): ({ string }, { [string]: number })
	local changed: { string } = {}
	local added: { [string]: number } = {}
	for _, currency in ipairs(CURRENCY_ORDER) do
		local amount = (grant[currency] or 0) + (if currency == "Gems" then extraGems or 0 else 0)
		if amount > 0 then
			added[currency] = addCurrency(data, currency, amount)
			table.insert(changed, currency)
		end
	end
	if grant.FreeWeaponPicks ~= nil and grant.FreeWeaponPicks ~= 0 then
		data.FreeWeaponPicks = math.max(0, Core.Balance(data, "FreeWeaponPicks") + grant.FreeWeaponPicks)
		table.insert(changed, "Weapons")
	end
	if grant.Weapons ~= nil and #grant.Weapons > 0 then
		for _, key in ipairs(grant.Weapons) do
			data.Weapons.Owned[key] = true
		end
		if not table.find(changed, "Weapons") then
			table.insert(changed, "Weapons")
		end
	end
	if grant.Cosmetics ~= nil and #grant.Cosmetics > 0 then
		for _, id in ipairs(grant.Cosmetics) do
			local def = COSMETICS.ById[id]
			-- Meisterschafts-Wraps haben keinen Besitz-Eintrag (B16.2), Standard-Items gehören allen
			if def and not (def.Kind == "Wrap" and def.Source == "Mastery") and def.Source ~= "Default" then
				data.Cosmetics.Owned[id] = true
			end
		end
		table.insert(changed, "Cosmetics")
	end
	if (grant.XpBoostSeconds or 0) > 0 then
		local base = math.max(now, tonumber(data.Boosts.XP2Until) or 0)
		data.Boosts.XP2Until = math.min(base + grant.XpBoostSeconds, now + MAX_BOOST_SECONDS)
		table.insert(changed, "Boosts")
	end
	return changed, added
end

-- Kosmetik kaufen: Preis nur aus Config (Shop.PriceOf). Gibt (ok, Sprachschlüssel, Preis) zurück.
function Core.BuyItem(
	data: any,
	id: string,
	currency: string,
	seasonId: number,
	featured: boolean
): (boolean, string, number?)
	local def = COSMETICS.ById[id]
	if def == nil then
		return false, "shop.unknownItem", nil
	end
	if currency ~= "Coins" and currency ~= "Gems" and currency ~= "Shards" then
		return false, "core.invalid", nil
	end
	if data.Cosmetics.Owned[id] == true then
		return false, "shop.owned", nil
	end
	if COSMETICS.IsExclusive(id, seasonId) then
		return false, "shop.exclusive", nil
	end
	local price = SHOP.PriceOf(COSMETICS, id, currency, seasonId, featured)
	if price == nil then
		return false, "shop.notForSale", nil
	end
	if not Core.Spend(data, currency, price) then
		return false, "shop.notEnough" .. currency, nil
	end
	data.Cosmetics.Owned[id] = true
	return true, "shop.bought", price
end

-- Eine Kiste öffnen. use = "Gems" | "Key"; randomAllowed: nur true erlaubt die Gem-Öffnung.
-- Gibt (ok, Sprachschlüssel, Ergebnis { Id, Rarity, Duplicate, Shards, Pity, Pity30 }) zurück.
function Core.OpenCrate(
	data: any,
	crate: any,
	use: string,
	randomAllowed: boolean?,
	random: any
): (boolean, string, any)
	if type(crate) ~= "table" or type(crate.Items) ~= "table" then
		return false, "shop.crateUnknown", nil
	end
	local currency: string, price: number
	if use == "Gems" then
		if randomAllowed ~= true then
			return false, "shop.restricted", nil -- unbekannt oder eingeschränkt (B20.2)
		end
		currency, price = "Gems", math.max(1, tonumber(crate.GemPrice) or 120)
	elseif use == "Key" then
		currency, price = "Keys", math.max(1, tonumber(crate.KeyPrice) or 1)
	else
		return false, "core.invalid", nil
	end
	if Core.Balance(data, currency) < price then
		return false, "shop.notEnough" .. currency, nil
	end
	local pityAfter = math.max(1, tonumber(crate.PityAfter) or 29)
	local pityActive = Core.Balance(data.Crates, "Pity") >= pityAfter
	local id = Odds.Roll(crate, random, pityActive)
	local item: any = nil
	for _, entry in ipairs(crate.Items) do
		if entry.Id == id then
			item = entry
			break
		end
	end
	if item == nil or COSMETICS.ById[id] == nil then
		return false, "core.error", nil -- kaputte Config: nichts abziehen
	end
	-- ab hier wird gebucht (kein Yield)
	Core.Spend(data, currency, price)
	local rarity = item.Rarity
	local duplicate = data.Cosmetics.Owned[id] == true
	local shards = 0
	if duplicate then
		shards = math.max(0, tonumber(SHOP.DupeShards[rarity]) or 0)
		addCurrency(data, "Shards", shards)
	else
		data.Cosmetics.Owned[id] = true
	end
	if table.find(crate.PityRarities or {}, rarity) then
		data.Crates.Pity = 0
	else
		data.Crates.Pity = Core.Balance(data.Crates, "Pity") + 1
	end
	data.Crates.Opened = Core.Balance(data.Crates, "Opened") + 1
	return true,
		"shop.crateOpened",
		{
			Id = id,
			Rarity = rarity,
			Duplicate = duplicate,
			Shards = shards,
			Pity = data.Crates.Pity,
			WasPity = pityActive,
			Currency = currency,
			Price = price,
		}
end

-- Wie viele Loadout-Vorlagen darf dieser Spielstand haben?
function Core.PresetMax(data: any, loadoutPlus: boolean): number
	if loadoutPlus then
		return PRESETS_PLUS
	end
	local slots = if isInteger(data.Loadouts.Slots) then data.Loadouts.Slots else PRESETS_BASE
	return math.clamp(slots, PRESETS_BASE, PRESETS_BASE + COIN_SLOTS_MAX)
end

local function defaultLoadout(): Loadout
	local cfg = Config.Weapons and Config.Weapons.DefaultLoadout
	if type(cfg) == "table" then
		local result = table.clone(FALLBACK_LOADOUT)
		for _, slot in ipairs(SLOTS) do
			if type(cfg[slot]) == "string" then
				result[slot] = cfg[slot]
			end
		end
		return result
	end
	return table.clone(FALLBACK_LOADOUT)
end

local function newPreset(index: number): { [string]: any }
	local base = defaultLoadout()
	return { Name = "Loadout " .. index, P = base.Primary, S = base.Secondary, M = base.Melee, U = base.Utility }
end

-- Vorlage bis Index anlegen (fehlende mit dem Standard-Loadout füllen)
function Core.EnsurePreset(data: any, index: number): { [string]: any }
	local presets = data.Loadouts.Presets
	for i = 1, math.min(index, PRESETS_PLUS) do
		if type(presets[i]) ~= "table" then
			presets[i] = newPreset(i)
		end
	end
	return presets[index]
end

function Core.PresetLoadout(preset: any): Loadout
	local base = defaultLoadout()
	if type(preset) ~= "table" then
		return base
	end
	for _, slot in ipairs(SLOTS) do
		local key = preset[SLOT_FIELD[slot]]
		if type(key) == "string" then
			base[slot] = key
		end
	end
	return base
end

-- Rampenlicht des Tages (deterministisch aus UTC-Tag + Saison)
function Core.Featured(day: number, seasonId: number): { string }
	return SHOP.PickFeatured(SHOP.FeaturedPool(COSMETICS, seasonId), day)
end

-- =====================================================================
-- 3) BESITZ & KOSMETIK
-- =====================================================================
function ShopService.Owns(p: Player, weaponKey: string): boolean
	local def = weaponDef(weaponKey)
	if def == nil then
		return false
	end
	if def.Free then
		return true
	end
	local data = dataOf(p)
	return data ~= nil
		and type(data.Weapons) == "table"
		and type(data.Weapons.Owned) == "table"
		and data.Weapons.Owned[weaponKey] == true
end

local function masteryTier(p: Player, weaponKey: string): number
	local ok, tier = try("ProgressionService", "MasteryTier", p, weaponKey)
	if ok and Util.IsFinite(tier) then
		return tier
	end
	-- Ersatz: eingelöste Stufe aus dem Spielstand (WP8-Feld, nur lesen)
	local data = dataOf(p)
	local entry = data
		and type(data.Weapons) == "table"
		and type(data.Weapons.Mastery) == "table"
		and data.Weapons.Mastery[weaponKey]
	return if type(entry) == "table" and isInteger(entry.T) then entry.T else 0
end

-- Wrap für DIESE Waffe erlaubt? (Meisterschaft prüft die Stufe dieser Waffe, B16.2)
local function canUseWrap(p: Player, wrapId: string, weaponKey: string): (boolean, string?)
	local def = COSMETICS.Wraps[wrapId]
	if def == nil then
		return false, "shop.unknownItem"
	end
	if def.Source == "Mastery" then
		local need = tonumber(def.MasteryTier) or 99
		if masteryTier(p, weaponKey) < need then
			return false, "shop.masteryLocked"
		end
		return true, nil
	end
	return ShopService.OwnsCosmetic(p, wrapId), "shop.notOwned"
end

function ShopService.OwnsCosmetic(p: Player, id: string): boolean
	if not validId(id) then
		return false
	end
	local def = COSMETICS.ById[id]
	if def == nil then
		return false
	end
	if def.Source == "Default" then
		return true
	end
	if def.Source == "VIP" then
		return hasPass(p, "VIP")
	end
	local data = dataOf(p)
	local owned = data ~= nil
		and type(data.Cosmetics) == "table"
		and type(data.Cosmetics.Owned) == "table"
		and data.Cosmetics.Owned[id] == true
	if owned then
		return true
	end
	if def.Source == "Mastery" then
		if def.Kind == "Title" and type(def.Weapon) == "string" then
			return masteryTier(p, def.Weapon) >= 9 -- Stufe IX: "<Waffe>-Meister"
		elseif def.Kind == "Wrap" then
			local need = tonumber(def.MasteryTier) or 99
			for _, key in ipairs(COSMETICS.WeaponKeys) do
				if masteryTier(p, key) >= need then
					return true
				end
			end
		end
	end
	return false
end

function ShopService.GetCosmetics(p: Player, weaponKey: string): { Skin: string, Wrap: string, Charm: string }
	local result = { Skin = "", Wrap = "", Charm = "" }
	local data = dataOf(p)
	if data == nil or type(weaponKey) ~= "string" or type(data.Cosmetics) ~= "table" then
		return result
	end
	local per = type(data.Cosmetics.PerWeapon) == "table" and data.Cosmetics.PerWeapon[weaponKey]
	if type(per) ~= "table" then
		return result
	end
	local skin = per.Skin
	if validId(skin) then
		local def = COSMETICS.Skins[skin]
		if def and def.Weapon == weaponKey and ShopService.OwnsCosmetic(p, skin) then
			result.Skin = skin
		end
	end
	local wrap = per.Wrap
	if validId(wrap) and canUseWrap(p, wrap, weaponKey) then
		result.Wrap = wrap
	end
	local charm = per.Charm
	if validId(charm) and COSMETICS.Charms[charm] and ShopService.OwnsCosmetic(p, charm) then
		result.Charm = charm
	end
	return result
end

function ShopService.Finisher(p: Player): string
	local data = dataOf(p)
	local id = data
		and type(data.Cosmetics) == "table"
		and type(data.Cosmetics.Equipped) == "table"
		and data.Cosmetics.Equipped.Finisher
	if validId(id) and COSMETICS.Finishers[id] and ShopService.OwnsCosmetic(p, id) then
		return id
	end
	return COSMETICS.Defaults.Finisher
end

function ShopService.Tracer(p: Player): string
	local data = dataOf(p)
	local id = data
		and type(data.Cosmetics) == "table"
		and type(data.Cosmetics.Equipped) == "table"
		and data.Cosmetics.Equipped.Tracer
	if validId(id) and COSMETICS.Tracers[id] and ShopService.OwnsCosmetic(p, id) then
		return id
	end
	return COSMETICS.Defaults.Tracer
end

function ShopService.TodayFeatured(): { string }
	local day = Util.UtcDay()
	local season = currentSeasonId()
	local cache = featuredCache
	if cache == nil or cache.Day ~= day or cache.Season ~= season then
		cache = { Day = day, Season = season, Ids = Core.Featured(day, season) }
		featuredCache = cache
	end
	return table.clone((cache :: any).Ids)
end

local function isFeatured(id: string): boolean
	return table.find(ShopService.TodayFeatured(), id) ~= nil
end

-- =====================================================================
-- 4) LOADOUT (validiert: Besitz, Not-Aus, Mutator)
-- =====================================================================
local function weaponOk(key: any, slot: SlotName, needOwned: boolean, p: Player?): boolean
	local def = weaponDef(key)
	if def == nil or def.Slot ~= slot or def.Enabled == false then
		return false
	end
	if needOwned and p ~= nil then
		return ShopService.Owns(p, key)
	end
	return true
end

local function randomWeapon(slot: SlotName): string?
	local list = Config.Weapons and Config.Weapons.List
	if type(list) ~= "table" then
		return nil
	end
	local options: { string } = {}
	for _, def in ipairs(list) do
		if type(def) == "table" and def.Slot == slot and def.Enabled ~= false and not def.AdminOnly then
			table.insert(options, def.Key)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

function ShopService.GetLoadout(p: Player, rules: Types.ContextRules?): Loadout
	local defaults = defaultLoadout()
	local data = dataOf(p)
	local chosen = defaults
	if data ~= nil and type(data.Loadouts) == "table" and type(data.Loadouts.Presets) == "table" then
		local active = if isInteger(data.Loadouts.Active) then data.Loadouts.Active else 1
		if active < 1 or active > Core.PresetMax(data, hasPass(p, "LoadoutPlus")) then
			active = 1 -- Vorlage über dem erlaubten Maximum (z. B. Loadout+ weg): erste nehmen
		end
		chosen = Core.PresetLoadout(data.Loadouts.Presets[active])
	end
	local ignoreOwnership = rules ~= nil and rules.IgnoreOwnership == true
	local forced = rules and rules.ForcedLoadout
	local result: Loadout = table.clone(defaults)
	for _, slot in ipairs(SLOTS) do
		local pick: string? = nil
		if rules ~= nil and rules.RandomLoadout then
			pick = randomWeapon(slot)
		end
		if pick == nil and type(forced) == "table" and weaponOk(forced[slot], slot, false, nil) then
			pick = forced[slot]
		end
		if pick == nil and weaponOk(chosen[slot], slot, not ignoreOwnership, p) then
			pick = chosen[slot]
		end
		if pick == nil and weaponOk(defaults[slot], slot, false, nil) then
			pick = defaults[slot]
		end
		if pick == nil then
			pick = randomWeapon(slot) -- Standardwaffe per Not-Aus gesperrt: irgendeine erlaubte
		end
		result[slot] = pick or defaults[slot]
	end
	return result
end

-- =====================================================================
-- 5) GRANT / SPEND (einziger Weg für Währung und Besitz, kein Yield)
-- =====================================================================
local function metricsEconomy(
	p: Player,
	flow: string,
	currency: string,
	amount: number,
	data: any,
	txType: string,
	sku: string?
)
	if amount <= 0 then
		return
	end
	try("MetricsService", "Economy", p, flow, currency, amount, Core.Balance(data, currency), txType, sku)
end

function ShopService.Grant(p: Player, grant: Types.Grant, reason: string): boolean
	local data = dataOf(p)
	if data == nil then
		return false
	end
	Core.Ensure(data)
	local ok, err = Core.ValidateGrant(data, grant)
	if not ok then
		warn(("[ShopService] Grant abgelehnt (%s, %s): %s"):format(p.Name, tostring(reason), tostring(err)))
		return false
	end
	local g: any = grant
	local extraGems = 0
	-- Pass-Teile zuerst: der externe Dienst darf scheitern, solange noch nichts geändert ist
	local tiers = g.PassTiers or 0
	if g.PassPremium == true or tiers > 0 then
		local progression = service("ProgressionService")
		if
			progression == nil
			or type(progression.GrantPassPremium) ~= "function"
			or type(progression.AddPassTiers) ~= "function"
		then
			warn("[ShopService] Grant mit Pass-Teil, aber ProgressionService fehlt – später erneut")
			return false
		end
		if g.PassPremium == true then
			local okCall, granted = pcall(progression.GrantPassPremium, p)
			if not okCall then
				warn("[ShopService] GrantPassPremium fehlgeschlagen: " .. tostring(granted))
				return false
			end
			if granted ~= true then
				extraGems += math.max(0, tonumber(SHOP.PassOwnedGems) or 500) -- schon Premium (B22.2)
			end
		end
		if tiers > 0 then
			local okCall, rest = pcall(progression.AddPassTiers, p, tiers)
			local restTiers = tiers
			if okCall and Util.IsFinite(rest) then
				restTiers = math.clamp(math.floor(rest), 0, tiers)
			elseif not okCall then
				warn("[ShopService] AddPassTiers fehlgeschlagen, Ersatz in Gems: " .. tostring(rest))
			end
			extraGems += restTiers * math.max(0, tonumber(SHOP.TierGemFallback) or 40)
		end
	end
	local changed, added = Core.ApplyGrant(data, g, os.time(), extraGems)
	for currency, amount in pairs(added) do
		metricsEconomy(p, "Source", currency, amount, data, tostring(reason), nil)
	end
	if #changed > 0 then
		markDirty(p, table.unpack(changed))
	end
	if table.find(changed, "Cosmetics") then
		ShopService.RefreshPlayer(p)
	end
	return true
end

function ShopService.Spend(p: Player, currency: Types.Currency, amount: number, reason: string): boolean
	local data = dataOf(p)
	if data == nil then
		return false
	end
	Core.Ensure(data)
	if not Core.Spend(data, currency, amount) then
		return false
	end
	metricsEconomy(p, "Sink", currency, amount, data, tostring(reason), nil)
	markDirty(p, currency)
	return true
end

-- Attribute Vip/Supporter (Namensschild/Chat, CharacterService/ChatClient lesen sie) + State
function ShopService.RefreshPlayer(p: Player)
	if p.Parent ~= Players then
		return
	end
	local vip = hasPass(p, "VIP")
	if p:GetAttribute("Vip") ~= vip then
		p:SetAttribute("Vip", vip)
	end
	local data = dataOf(p)
	local supporter = false
	if data ~= nil then
		local purchases = data.Purchases
		supporter = (type(purchases) == "table" and isInteger(purchases.Supporter) and purchases.Supporter > 0)
			or (
				type(data.Cosmetics) == "table"
				and type(data.Cosmetics.Owned) == "table"
				and data.Cosmetics.Owned.TT_Supporter == true
			)
	end
	if p:GetAttribute("Supporter") ~= supporter then
		p:SetAttribute("Supporter", supporter)
	end
	markDirty(p, "Loadouts", "Cosmetics")
end

-- =====================================================================
-- 6) REQUEST-HANDLER (C9) – Ablauf: Typprüfung -> Daten -> Prüfen -> Buchen (ohne Yield)
-- =====================================================================
local function withBusy(handler: (Player, any) -> Reply): (Player, any) -> Reply
	return function(p: Player, arg: any): Reply
		if busy[p] then
			return fail(p, "shop.busy")
		end
		busy[p] = true
		local ok, result = pcall(handler, p, arg)
		busy[p] = nil
		if not ok then
			error(result, 0)
		end
		return result
	end
end

local function loadedData(p: Player): any
	local data = dataOf(p)
	if data ~= nil then
		Core.Ensure(data)
	end
	return data
end

local function handleBuyWeapon(p: Player, arg: any): Reply
	local def = weaponDef(arg)
	if def == nil then
		return fail(p, "shop.unknownWeapon")
	end
	local key = def.Key
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	if def.Free then
		return fail(p, "shop.weaponFree")
	end
	if data.Weapons.Owned[key] == true then
		return fail(p, "shop.owned")
	end
	local price = math.floor(tonumber(def.Price) or 0)
	if price <= 0 then
		return fail(p, "shop.notForSale")
	end
	local hadBought = false
	for ownedKey in pairs(data.Weapons.Owned) do
		local ownedDef = Config.Weapon(ownedKey)
		if ownedDef and not ownedDef.Free then
			hadBought = true
			break
		end
	end
	if not Core.Spend(data, "Coins", price) then
		return fail(p, "shop.notEnoughCoins")
	end
	data.Weapons.Owned[key] = true
	metricsEconomy(p, "Sink", "Coins", price, data, "Weapon", key)
	markDirty(p, "Coins", "Weapons")
	try("RewardService", "Track", p, "NewWeapon", 1, { Weapon = key })
	if not hadBought then
		try("MetricsService", "Funnel", p, 11, "FirstWeaponBought")
	end
	return { Ok = true, Message = text(p, "shop.weaponBought", Lang.Pick(langOf(p), def.Name)) }
end

local function handleBuyItem(p: Player, arg: any): Reply
	if type(arg) ~= "table" or not validId(arg.Id) or type(arg.Currency) ~= "string" then
		return fail(p, "core.invalid")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local id: string = arg.Id
	local featured = arg.Featured == true and arg.Currency == "Gems" and isFeatured(id)
	local ok, key, price = Core.BuyItem(data, id, arg.Currency, currentSeasonId(), featured)
	if not ok then
		return fail(p, key)
	end
	metricsEconomy(p, "Sink", arg.Currency, price or 0, data, if featured then "Featured" else "Catalog", id)
	markDirty(p, arg.Currency, "Cosmetics")
	local def = COSMETICS.ById[id]
	return { Ok = true, Message = text(p, key, Lang.Pick(langOf(p), def.Name)) }
end

local function announceCrateFind(p: Player, result: any)
	if result.Rarity ~= "Legendary" and result.Rarity ~= "Mythic" then
		return
	end
	local monetization = service("MonetizationService")
	local function allowed(target: Player): boolean
		if monetization == nil or type(monetization.RandomAllowed) ~= "function" then
			return false
		end
		local ok, value = pcall(monetization.RandomAllowed, target)
		return ok and value == true -- nur an Spieler, bei denen Zufallsitems erlaubt sind (B20.2)
	end
	local okAnnounce =
		try("CommunityService", "Announce", "shop.crateFound", { p.DisplayName, rarityName(result.Rarity) }, allowed)
	if not okAnnounce then
		local stateService = service("PlayerStateService")
		if stateService and type(stateService.EffectAll) == "function" then
			stateService.EffectAll(
				"CrateFound",
				1,
				{ Name = p.DisplayName, ItemId = result.Id, Rarity = result.Rarity },
				allowed
			)
		end
	end
end

local function handleOpenCrate(p: Player, arg: any): Reply
	if type(arg) ~= "table" or type(arg.Crate) ~= "string" or (arg.Use ~= "Gems" and arg.Use ~= "Key") then
		return fail(p, "core.invalid")
	end
	local crate = SHOP.Crates[arg.Crate]
	if type(crate) ~= "table" then
		return fail(p, "shop.crateUnknown")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local allowed: boolean? = nil
	local monetization = service("MonetizationService")
	if monetization and type(monetization.RandomAllowed) == "function" then
		local ok, value = pcall(monetization.RandomAllowed, p)
		allowed = if ok then value else nil
	end
	local ok, key, result = Core.OpenCrate(data, crate, arg.Use, allowed, rng)
	if not ok then
		return fail(p, key)
	end
	metricsEconomy(p, "Sink", result.Currency, result.Price, data, "Crate", arg.Crate)
	if result.Shards > 0 then
		metricsEconomy(p, "Source", "Shards", result.Shards, data, "CrateDuplicate", result.Id)
	end
	markDirty(p, result.Currency, "Shards", "Cosmetics", "Crates")
	announceCrateFind(p, result)
	return {
		Ok = true,
		Result = { Id = result.Id, Rarity = result.Rarity, Duplicate = result.Duplicate, Shards = result.Shards },
	}
end

local function handleEquipCosmetic(p: Player, arg: any): Reply
	if type(arg) ~= "table" or type(arg.Kind) ~= "string" or not EQUIP_KINDS[arg.Kind] or type(arg.Id) ~= "string" then
		return fail(p, "core.invalid")
	end
	local kind: string, id: string = arg.Kind, arg.Id
	if #id > MAX_ID_LEN then
		return fail(p, "core.invalid")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local cos = data.Cosmetics
	if id ~= "" then
		local def = COSMETICS.ById[id]
		if def == nil or def.Kind ~= kind then
			return fail(p, "shop.unknownItem")
		end
	end
	if PER_WEAPON_KINDS[kind] then
		local weaponKey = arg.Weapon
		if
			not validId(weaponKey) or (weaponDef(weaponKey) == nil and not table.find(COSMETICS.WeaponKeys, weaponKey))
		then
			return fail(p, "shop.unknownWeapon")
		end
		if id ~= "" then
			if kind == "Skin" then
				if COSMETICS.Skins[id].Weapon ~= weaponKey then
					return fail(p, "shop.wrongWeapon")
				end
				if not ShopService.OwnsCosmetic(p, id) then
					return fail(p, "shop.notOwned")
				end
			elseif kind == "Wrap" then
				local okWrap, why = canUseWrap(p, id, weaponKey)
				if not okWrap then
					return fail(p, why or "shop.notOwned", tonumber(COSMETICS.Wraps[id].MasteryTier) or 0)
				end
			elseif not ShopService.OwnsCosmetic(p, id) then
				return fail(p, "shop.notOwned")
			end
		end
		local per = cos.PerWeapon[weaponKey]
		if type(per) ~= "table" then
			per = { Skin = "", Wrap = "", Charm = "" }
			cos.PerWeapon[weaponKey] = per
		end
		per[kind] = id
	else
		if id == "" then
			id = if kind == "Title" then "" else COSMETICS.Defaults[kind]
		elseif not ShopService.OwnsCosmetic(p, id) then
			return fail(p, "shop.notOwned")
		end
		cos.Equipped[kind] = id
	end
	markDirty(p, "Cosmetics")
	return { Ok = true }
end

local function checkLoadoutArg(data: any, loadout: any): (boolean, string?)
	if type(loadout) ~= "table" then
		return false, "core.invalid"
	end
	for _, slot in ipairs(SLOTS) do
		local key = loadout[slot]
		local def = weaponDef(key)
		if def == nil then
			return false, "shop.unknownWeapon"
		end
		if def.Slot ~= slot then
			return false, "shop.slotWrong"
		end
		if not def.Free and data.Weapons.Owned[key] ~= true then
			return false, "shop.notOwned"
		end
	end
	return true, nil
end

local function handleSetLoadout(p: Player, arg: any): Reply
	if type(arg) ~= "table" or not isInteger(arg.Index) then
		return fail(p, "core.invalid")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local max = Core.PresetMax(data, hasPass(p, "LoadoutPlus"))
	local index: number = arg.Index
	if index < 1 or index > max then
		return fail(p, "core.invalid")
	end
	local ok, why = checkLoadoutArg(data, arg.Loadout)
	if not ok then
		return fail(p, why or "core.invalid")
	end
	local preset = Core.EnsurePreset(data, index)
	for _, slot in ipairs(SLOTS) do
		preset[SLOT_FIELD[slot]] = arg.Loadout[slot]
	end
	markDirty(p, "Loadouts")
	try("RewardService", "Track", p, "LoadoutEdit", 1, nil)
	return { Ok = true, Message = text(p, "shop.loadoutSaved") }
end

local function handleSelectPreset(p: Player, arg: any): Reply
	if not isInteger(arg) then
		return fail(p, "core.invalid")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local max = Core.PresetMax(data, hasPass(p, "LoadoutPlus"))
	if arg < 1 or arg > max then
		return fail(p, "core.invalid")
	end
	Core.EnsurePreset(data, arg)
	data.Loadouts.Active = arg
	markDirty(p, "Loadouts")
	return { Ok = true }
end

local function handleRenamePreset(p: Player, arg: any): Reply
	if type(arg) ~= "table" or not isInteger(arg.Index) or type(arg.Name) ~= "string" then
		return fail(p, "core.invalid")
	end
	if not hasPass(p, "LoadoutPlus") then
		return fail(p, "shop.needLoadoutPlus")
	end
	if #arg.Name > 200 then
		return fail(p, "shop.nameInvalid", PRESET_NAME_MAX)
	end
	local name = string.gsub(string.gsub(arg.Name, "[%c]", ""), "^%s*(.-)%s*$", "%1")
	local length = utf8.len(name)
	if length == nil or length < 1 or length > PRESET_NAME_MAX then
		return fail(p, "shop.nameInvalid", PRESET_NAME_MAX)
	end
	-- Filter (yieldet) VOR dem Schreiben; danach Spielstand neu holen und erneut prüfen
	local okFilter, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, p.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okFilter or type(filtered) ~= "string" or filtered == "" then
		return fail(p, "shop.filterFailed")
	end
	local data = loadedData(p)
	if data == nil or p.Parent ~= Players then
		return fail(p, "core.loading")
	end
	local max = Core.PresetMax(data, hasPass(p, "LoadoutPlus"))
	if arg.Index < 1 or arg.Index > max then
		return fail(p, "core.invalid")
	end
	Core.EnsurePreset(data, arg.Index).Name = filtered
	markDirty(p, "Loadouts")
	return { Ok = true, Message = text(p, "shop.renamed") }
end

-- "Zufall aus Favoriten" (Loadout+): wählt zufällig eine der anderen gültigen Vorlagen
local function handleRandomLoadout(p: Player, _arg: any): Reply
	if not hasPass(p, "LoadoutPlus") then
		return fail(p, "shop.needLoadoutPlus")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	local max = Core.PresetMax(data, true)
	local options: { number } = {}
	for i = 1, max do
		local preset = data.Loadouts.Presets[i]
		if i ~= data.Loadouts.Active and type(preset) == "table" then
			table.insert(options, i)
		end
	end
	if #options == 0 then
		return fail(p, "shop.randomNone")
	end
	local index = options[rng:NextInteger(1, #options)]
	data.Loadouts.Active = index
	markDirty(p, "Loadouts")
	local preset = data.Loadouts.Presets[index]
	return {
		Ok = true,
		Index = index,
		Message = text(p, "shop.randomLoadout", tostring(preset.Name or ("Loadout " .. index))),
	}
end

local function handleBuyPresetSlot(p: Player, _arg: any): Reply
	if hasPass(p, "LoadoutPlus") then
		return fail(p, "shop.presetPassHas")
	end
	local data = loadedData(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	if data.Loadouts.Slots >= PRESETS_BASE + COIN_SLOTS_MAX then
		return fail(p, "shop.presetMax")
	end
	if not Core.Spend(data, "Coins", PRESET_SLOT_COINS) then
		return fail(p, "shop.notEnoughCoins")
	end
	data.Loadouts.Slots += 1
	Core.EnsurePreset(data, data.Loadouts.Slots)
	metricsEconomy(p, "Sink", "Coins", PRESET_SLOT_COINS, data, "PresetSlot", nil)
	markDirty(p, "Coins", "Loadouts")
	return { Ok = true, Message = text(p, "shop.presetBought") }
end

-- =====================================================================
-- 7) STATE-SCHLÜSSEL
-- =====================================================================
local function provide(key: string, fn: (Player) -> any)
	local stateService = service("PlayerStateService")
	if stateService and type(stateService.Provide) == "function" then
		stateService.Provide(key, fn)
	end
end

local function nextUtcMidnight(): number
	return (math.floor(os.time() / 86400) + 1) * 86400
end

local function registerState()
	for _, currency in ipairs(CURRENCY_ORDER) do
		provide(currency, function(p: Player)
			return Core.Balance(dataOf(p), currency)
		end)
	end
	provide("Weapons", function(p: Player)
		local data = dataOf(p)
		local owned = data and type(data.Weapons) == "table" and data.Weapons.Owned
		return {
			Owned = if type(owned) == "table" then owned else {},
			FreePicks = Core.Balance(data, "FreeWeaponPicks"),
		}
	end)
	provide("Loadouts", function(p: Player)
		local data = dataOf(p)
		if data == nil or type(data.Loadouts) ~= "table" then
			return { Active = 1, Slots = PRESETS_BASE, Max = PRESETS_BASE, Presets = {} }
		end
		local plus = hasPass(p, "LoadoutPlus")
		return {
			Active = data.Loadouts.Active,
			Slots = data.Loadouts.Slots,
			Max = Core.PresetMax(data, plus),
			Plus = plus,
			SlotCoins = PRESET_SLOT_COINS,
			CoinSlotsMax = PRESETS_BASE + COIN_SLOTS_MAX,
			Presets = data.Loadouts.Presets,
		}
	end)
	provide("Cosmetics", function(p: Player)
		local data = dataOf(p)
		local cos = data and data.Cosmetics
		if type(cos) ~= "table" then
			return { Owned = {}, Equipped = {}, PerWeapon = {} }
		end
		return { Owned = cos.Owned, Equipped = cos.Equipped, PerWeapon = cos.PerWeapon }
	end)
	provide("Crates", function(p: Player)
		local data = dataOf(p)
		local crates = data and data.Crates
		local pityAfter = tonumber(SHOP.Crates.S1 and SHOP.Crates.S1.PityAfter) or 29
		return {
			Pity = if type(crates) == "table" then Core.Balance(crates, "Pity") else 0,
			Opened = if type(crates) == "table" then Core.Balance(crates, "Opened") else 0,
			PityAfter = pityAfter,
		}
	end)
	provide("Featured", function(_p: Player)
		return {
			Day = Util.UtcDay(),
			Ids = ShopService.TodayFeatured(),
			EndsAt = nextUtcMidnight(),
			Discount = SHOP.FeaturedDiscount,
		}
	end)
end

-- =====================================================================
-- 8) INIT / START
-- =====================================================================
local function onReady(p: Player)
	local data = dataOf(p)
	if data == nil then
		return
	end
	Core.Ensure(data)
	local max = Core.PresetMax(data, hasPass(p, "LoadoutPlus"))
	Core.EnsurePreset(data, math.max(PRESETS_BASE, data.Loadouts.Slots))
	if data.Loadouts.Active < 1 or data.Loadouts.Active > max then
		data.Loadouts.Active = 1
	end
	ShopService.RefreshPlayer(p)
end

function ShopService.Init(services: any)
	Services = services
	registerState()
	local stateService = service("PlayerStateService")
	if stateService == nil or type(stateService.Handle) ~= "function" then
		warn("[ShopService] PlayerStateService fehlt – keine Shop-Anfragen")
		return
	end
	local handle = stateService.Handle
	handle("SetLoadout", handleSetLoadout, { Rate = 4, Per = 1 })
	handle("SelectPreset", handleSelectPreset, { Rate = 4, Per = 1 })
	handle("RenamePreset", handleRenamePreset, { Rate = 4, Per = 1 })
	handle("RandomLoadout", handleRandomLoadout, { Rate = 4, Per = 1 })
	handle("BuyWeapon", withBusy(handleBuyWeapon), { Rate = 2, Per = 1 })
	handle("BuyItem", withBusy(handleBuyItem), { Rate = 2, Per = 1 })
	handle("OpenCrate", withBusy(handleOpenCrate), { Rate = 2, Per = 1 })
	handle("EquipCosmetic", handleEquipCosmetic, { Rate = 6, Per = 1 })
	handle("BuyPresetSlot", withBusy(handleBuyPresetSlot), { Rate = 1, Per = 1 })
end

function ShopService.Start()
	local stateService = service("PlayerStateService")
	if stateService and type(stateService.OnReady) == "function" then
		stateService.OnReady(onReady)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		busy[p] = nil
	end)
	-- neuer UTC-Tag -> neues Rampenlicht an alle
	local shownDay = Util.UtcDay()
	Scheduler.Every("ShopFeatured", FEATURED_CHECK_HZ, function()
		local day = Util.UtcDay()
		if day ~= shownDay then
			shownDay = day
			for _, p in ipairs(Players:GetPlayers()) do
				markDirty(p, "Featured")
			end
		end
	end)
end

return ShopService
