--!strict
-- =====================================================================
--  CLUTCH CLASH – Kisten-Quoten (Shared/Odds)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B20.1 + C6.3.
--  Anzeige-Tabelle (Shop "Details & Quoten") und Server-Wurf kommen aus DERSELBEN Tabelle
--  (Config.Shop.Crates.S1) – so stimmen angezeigte Quoten immer mit dem Server überein.
--  Reines Modul (keine Roblox-Dienste) -> mit der Luau-CLI testbar (tests/odds.test.luau).
--
--  Öffentliche API:
--    Odds.Table(crate): { { Id, Percent, Hundredths, Weight, Rarity? } }   Summe exakt 100.00
--    Odds.PityTable(crate): dito, nur die Garantie-Items (Legendary + Mythic)
--    Odds.RarityTable(crate, pity?): { { Rarity, Hundredths, Percent, Count } }  Summe exakt 100.00
--    Odds.Roll(crate, rng, pityActive): string     rng:NextInteger(1, Summe) (Server: Random.new())
--    Odds.Validate(crate): (boolean, string?)        Gewichte ganzzahlig > 0, Summe 10000
--    Odds.PityItems(crate): { item }                 Items der Garantie-Seltenheiten
--    Odds.FormatPercent(hundredths, decimalSep?): string   500 -> "5.00" (oder "5,00")
--  Rundung: Hundertstel-Prozent nach dem Verfahren der größten Reste (Summe immer genau 10000).
-- =====================================================================

local Odds = {}

export type CrateItem = { Id: string, Weight: number, Rarity: string? }
export type Crate = { Items: { CrateItem }, PityRarities: { string }?, PityAfter: number?, [string]: any }
export type OddsRow = { Id: string, Percent: number, Hundredths: number, Weight: number, Rarity: string? }
export type RarityRow = { Rarity: string, Percent: number, Hundredths: number, Count: number }

Odds.TOTAL = 10000 -- Basispunkte (= 100,00 %)

local function itemsOf(crate: any): { CrateItem }
	if type(crate) ~= "table" or type(crate.Items) ~= "table" then
		return {}
	end
	return crate.Items
end

local function validWeight(w: any): boolean
	return type(w) == "number" and w == w and w > 0 and w ~= math.huge and w % 1 == 0
end

-- Gewichte -> Hundertstel-Prozent (Summe genau 10000) nach der Methode der größten Reste.
-- Gleichstand bei den Resten: größeres Gewicht zuerst, dann Reihenfolge in der Liste.
local function apportion(weights: { number }): { number }
	local total = 0
	for _, w in ipairs(weights) do
		total += w
	end
	local result: { number } = table.create(#weights, 0)
	if total <= 0 then
		return result
	end
	local remainders: { { Index: number, Rest: number, Weight: number } } = {}
	local assigned = 0
	for i, w in ipairs(weights) do
		local exact = w * Odds.TOTAL / total
		local floor = math.floor(exact + 1e-9)
		result[i] = floor
		assigned += floor
		table.insert(remainders, { Index = i, Rest = exact - floor, Weight = w })
	end
	table.sort(remainders, function(a, b)
		if math.abs(a.Rest - b.Rest) > 1e-9 then
			return a.Rest > b.Rest
		end
		if a.Weight ~= b.Weight then
			return a.Weight > b.Weight
		end
		return a.Index < b.Index
	end)
	local missing = Odds.TOTAL - assigned
	local i = 1
	while missing > 0 and #remainders > 0 do -- höchstens #weights Schritte (Reste < 1 je Eintrag)
		local entry = remainders[((i - 1) % #remainders) + 1]
		result[entry.Index] += 1
		missing -= 1
		i += 1
	end
	return result
end

local function buildRows(items: { CrateItem }): { OddsRow }
	local weights: { number } = {}
	for _, item in ipairs(items) do
		table.insert(weights, if validWeight(item.Weight) then item.Weight else 0)
	end
	local hundredths = apportion(weights)
	local rows: { OddsRow } = {}
	for i, item in ipairs(items) do
		table.insert(rows, {
			Id = item.Id,
			Percent = hundredths[i] / 100,
			Hundredths = hundredths[i],
			Weight = weights[i],
			Rarity = item.Rarity,
		})
	end
	return rows
end

-- Items der Garantie-Seltenheiten (Legendary + Mythic)
function Odds.PityItems(crate: any): { CrateItem }
	local result: { CrateItem } = {}
	local rarities = if type(crate) == "table" and type(crate.PityRarities) == "table" then crate.PityRarities else {}
	for _, item in ipairs(itemsOf(crate)) do
		if item.Rarity ~= nil and table.find(rarities, item.Rarity) ~= nil then
			table.insert(result, item)
		end
	end
	return result
end

-- Anzeige-Tabelle: { Id, Percent } je Item, Summe exakt 100.00 (bei Summe 10000 = Gewicht/100)
function Odds.Table(crate: { Items: { { Id: string, Weight: number } } }): { OddsRow }
	return buildRows(itemsOf(crate))
end

-- Garantie-Tabelle (30. Öffnung): nur Legendary + Mythic, z. B. 250/250/100 -> 41.67/41.67/16.66
function Odds.PityTable(crate: any): { OddsRow }
	return buildRows(Odds.PityItems(crate))
end

-- Summen pro Seltenheit (Reihenfolge wie in der Kiste), Summe exakt 100.00
function Odds.RarityTable(crate: any, pity: boolean?): { RarityRow }
	local items = if pity then Odds.PityItems(crate) else itemsOf(crate)
	local order: { string } = {}
	local weightOf: { [string]: number } = {}
	local countOf: { [string]: number } = {}
	for _, item in ipairs(items) do
		local rarity = item.Rarity or "?"
		if weightOf[rarity] == nil then
			table.insert(order, rarity)
			weightOf[rarity] = 0
			countOf[rarity] = 0
		end
		weightOf[rarity] += if validWeight(item.Weight) then item.Weight else 0
		countOf[rarity] += 1
	end
	local weights: { number } = {}
	for _, rarity in ipairs(order) do
		table.insert(weights, weightOf[rarity])
	end
	local hundredths = apportion(weights)
	local rows: { RarityRow } = {}
	for i, rarity in ipairs(order) do
		table.insert(rows, {
			Rarity = rarity,
			Hundredths = hundredths[i],
			Percent = hundredths[i] / 100,
			Count = countOf[rarity],
		})
	end
	return rows
end

-- Ein Wurf. pityActive -> nur unter den Garantie-Items (mit ihren normalen Gewichten).
-- rng braucht NextInteger(min, max) (Roblox: Random.new(); Tests: eigene Tabelle).
function Odds.Roll(crate: any, rng: Random, pityActive: boolean): string
	local items = if pityActive then Odds.PityItems(crate) else itemsOf(crate)
	if #items == 0 then
		items = itemsOf(crate) -- Garantie ohne passende Items: normaler Wurf (Validate meldet das)
	end
	local total = 0
	for _, item in ipairs(items) do
		if validWeight(item.Weight) then
			total += item.Weight
		end
	end
	assert(total > 0, "[Odds] Kiste ohne gültige Gewichte")
	local roll = (rng :: any):NextInteger(1, total)
	if type(roll) ~= "number" or roll ~= roll then
		roll = 1
	end
	roll = math.clamp(math.floor(roll), 1, total)
	local last = items[1].Id
	for _, item in ipairs(items) do
		if validWeight(item.Weight) then
			last = item.Id
			roll -= item.Weight
			if roll <= 0 then
				return item.Id
			end
		end
	end
	return last
end

-- Gewichte ganzzahlig > 0, eindeutige Ids, Summe genau 10000, Garantie-Items vorhanden
function Odds.Validate(crate: any): (boolean, string?)
	local items = itemsOf(crate)
	if #items == 0 then
		return false, "keine Items"
	end
	local total = 0
	local seen: { [string]: boolean } = {}
	for i, item in ipairs(items) do
		if type(item.Id) ~= "string" or item.Id == "" then
			return false, ("Item %d: Id fehlt"):format(i)
		end
		if seen[item.Id] then
			return false, "doppelte Id " .. item.Id
		end
		seen[item.Id] = true
		if not validWeight(item.Weight) then
			return false, ("Item %s: Gewicht muss eine ganze Zahl > 0 sein"):format(item.Id)
		end
		total += item.Weight
	end
	if total ~= Odds.TOTAL then
		return false, ("Gewichte ergeben %d statt %d"):format(total, Odds.TOTAL)
	end
	if type(crate.PityAfter) == "number" and #Odds.PityItems(crate) == 0 then
		return false, "Garantie ohne Legendary/Mythic-Items"
	end
	return true, nil
end

-- 500 -> "5.00", 4167 -> "41.67" (decimalSep "," für Deutsch)
function Odds.FormatPercent(hundredths: number, decimalSep: string?): string
	local h = if type(hundredths) == "number" and hundredths == hundredths then math.floor(hundredths + 0.5) else 0
	local whole = math.floor(h / 100)
	local frac = h % 100
	return ("%d%s%02d"):format(whole, decimalSep or ".", frac)
end

return Odds
