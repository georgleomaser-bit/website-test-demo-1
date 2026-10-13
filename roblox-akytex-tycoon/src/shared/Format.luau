--!strict
-- =====================================================================
--  AKYTEX TYCOON – Zahlen-Anzeige DE/EN (Shared/Format)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C6.1 + §C15 (Zahlen) + Muss-Regel 9 (MAX ab 9e15).
--  Reines Modul (keine Roblox-Dienste) -> mit der Luau-CLI testbar (tests/format.test.luau).
--  DE: Tausender "." · Dezimal "," · Kürzel Tsd./Mio./Mrd./Bio./Brd. (mit Leerzeichen)
--  EN: Tausender "," · Dezimal "." · Kürzel K/M/B/T/Qa (ohne Leerzeichen)
--  Geld-Kürzel werden ABGESCHNITTEN (nie mehr anzeigen als da ist, nie "1000 Tsd."), Prozente/Multiplikatoren gerundet.
--
--  Öffentliche API:
--    Format.Credits(n, lang): string              "9.999" · "1,25 Mio." / "1.25M"; |n| ≥ 9e15 -> "MAX"
--    Format.Aky(cents, lang, compact?): string    "1.234,56 AKY" / "1,234.56 AKY"; compact ab 1.000 AKY: "1,23 Tsd. AKY" / "1.23K AKY"
--    Format.Price(cents, lang): string            "123,45" / "123.45" (mit Tausendertrennzeichen)
--    Format.Pct(fraction, lang, digits?, signed?) "+2,35 %" / "+2.35%" (fraction 0.0235; digits 0–4, Std. 2)
--    Format.Mult(x, lang): string                 "x7,4" / "x7.4" (max. 2 Nachkommastellen, Nullen weg)
--    Format.Duration(seconds, lang): string       "3:07" · "5 h 12 min" · DE "2 T 3 h" / EN "2 d 3 h"
--    Format.Compact(n, lang): string              "12,3 Tsd." / "12.3K" … bis Brd./Qa; |n| < 1000 ganzzahlig; ≥ 9e15 "MAX"
--    Format.Int(n, lang): string                  ganze Zahl mit Tausendertrennzeichen ("1.234.567")
--  Ungültige Eingaben (NaN, ±unendlich, kein number) ergeben "0" bzw. die 0-Darstellung – nie ein Fehler.
-- =====================================================================

local Format = {}

type Lang = "de" | "en"

local MAX_MONEY = 9e15
local EPS = 1e-9
local HUGE = math.huge

local SUFFIX: { [string]: { string } } = {
	de = { "Tsd.", "Mio.", "Mrd.", "Bio.", "Brd." },
	en = { "K", "M", "B", "T", "Qa" },
}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

local function langOf(lang: any): Lang
	if lang == "de" then
		return "de"
	end
	return "en"
end

-- (Tausender, Dezimal)
local function separators(lang: Lang): (string, string)
	if lang == "de" then
		return ".", ","
	end
	return ",", "."
end

-- ganze Zahl ≥ 0 mit Tausendertrennzeichen
local function groupDigits(n: number, sep: string): string
	local digits = string.format("%.0f", math.floor(n))
	if #digits <= 3 then
		return digits
	end
	local head = #digits % 3
	local parts: { string } = {}
	if head > 0 then
		table.insert(parts, string.sub(digits, 1, head))
	end
	for i = head + 1, #digits, 3 do
		table.insert(parts, string.sub(digits, i, i + 2))
	end
	return table.concat(parts, sep)
end

-- "1.50" -> "1.5", "2.00" -> "2" (nur für Texte mit Punkt als Dezimalzeichen)
local function stripZeros(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

local function withDecimal(text: string, dec: string): string
	if dec == "." then
		return text
	end
	return (string.gsub(text, "%.", dec))
end

-- ---------------------------------------------------------------------
-- GANZE ZAHLEN & KÜRZEL
-- ---------------------------------------------------------------------
function Format.Int(n: number, lang: Lang): string
	if not finite(n) then
		return "0"
	end
	local thousands = separators(langOf(lang))
	local negative = n <= -1 -- -0,5 -> "0"
	local text = groupDigits(math.abs(n), thousands)
	return if negative then "-" .. text else text
end

function Format.Compact(n: number, lang: Lang): string
	if not finite(n) then
		return "0"
	end
	local language: Lang = langOf(lang)
	local negative = n <= -1
	local value = math.abs(n)
	if value >= MAX_MONEY then
		return if negative then "-MAX" else "MAX"
	end
	if value < 1000 then
		return Format.Int(n, language)
	end
	local suffixes = SUFFIX[language]
	-- Stufe über Vergleiche (kein wiederholtes Teilen -> keine Rundungsfehler an den Grenzen)
	local index, scale = 1, 1000
	while index < #suffixes and value * (1 + EPS) >= scale * 1000 do
		scale *= 1000
		index += 1
	end
	local v = value / scale
	local text: string
	if v >= 100 then
		text = string.format("%.0f", math.floor(v * (1 + EPS)))
	elseif v >= 10 then
		text = string.format("%.1f", math.floor(v * 10 + EPS) / 10)
	else
		text = string.format("%.2f", math.floor(v * 100 + EPS) / 100)
	end
	local _, dec = separators(language)
	text = withDecimal(stripZeros(text), dec)
	local spacer = if language == "de" then " " else ""
	return (if negative then "-" else "") .. text .. spacer .. suffixes[index]
end

-- ---------------------------------------------------------------------
-- GELD
-- ---------------------------------------------------------------------
function Format.Credits(n: number, lang: Lang): string
	if not finite(n) then
		return "0"
	end
	local value = math.abs(n)
	if value >= MAX_MONEY then
		return if n < 0 then "-MAX" else "MAX"
	end
	if value < 10000 then
		return Format.Int(n, lang)
	end
	return Format.Compact(n, lang)
end

function Format.Price(cents: number, lang: Lang): string
	local language: Lang = langOf(lang)
	local thousands, dec = separators(language)
	if not finite(cents) then
		return "0" .. dec .. "00"
	end
	local whole = math.floor(math.abs(cents) + 0.5) -- ganze Cent
	local units = math.floor(whole / 100)
	local rest = whole - units * 100
	local text = groupDigits(units, thousands) .. dec .. string.format("%02d", rest)
	return if cents < 0 and whole > 0 then "-" .. text else text
end

function Format.Aky(cents: number, lang: Lang, compact: boolean?): string
	local language: Lang = langOf(lang)
	if not finite(cents) then
		return Format.Price(0, language) .. " AKY"
	end
	if math.abs(cents) >= MAX_MONEY then
		return (if cents < 0 then "-MAX" else "MAX") .. " AKY"
	end
	if compact == true and math.abs(cents) >= 100000 then -- ab 1.000 AKY kurz
		return Format.Compact(cents / 100, language) .. " AKY"
	end
	return Format.Price(cents, language) .. " AKY"
end

-- ---------------------------------------------------------------------
-- VERHÄLTNISSE (gerundet)
-- ---------------------------------------------------------------------
function Format.Pct(fraction: number, lang: Lang, digits: number?, signed: boolean?): string
	local language: Lang = langOf(lang)
	local thousands, dec = separators(language)
	local places = if finite(digits) then math.clamp(math.floor(digits :: number), 0, 4) else 2
	local percent = if finite(fraction) then fraction * 100 else 0
	local factor = 10 ^ places
	local scaled = math.floor(math.abs(percent) * factor + 0.5)
	local units = math.floor(scaled / factor)
	local rest = scaled - units * factor
	local text = groupDigits(units, thousands)
	if places > 0 then
		text ..= dec .. string.format("%0" .. places .. "d", rest)
	end
	local sign = ""
	if scaled > 0 then
		if percent < 0 then
			sign = "-"
		elseif signed == true then
			sign = "+"
		end
	end
	local unit = if language == "de" then " %" else "%"
	return sign .. text .. unit
end

function Format.Mult(x: number, lang: Lang): string
	local language: Lang = langOf(lang)
	local _, dec = separators(language)
	if not finite(x) then
		return "x1"
	end
	local rounded = math.floor(math.abs(x) * 100 + 0.5) / 100
	local text = withDecimal(stripZeros(string.format("%.2f", rounded)), dec)
	return "x" .. (if x < 0 and rounded > 0 then "-" else "") .. text
end

-- ---------------------------------------------------------------------
-- DAUER
-- ---------------------------------------------------------------------
function Format.Duration(seconds: number, lang: Lang): string
	local language: Lang = langOf(lang)
	local total = if finite(seconds) then math.clamp(math.floor(seconds), 0, 999999999) else 0
	if total < 3600 then
		return string.format("%d:%02d", math.floor(total / 60), total % 60)
	end
	if total < 86400 then
		local h = math.floor(total / 3600)
		local m = math.floor((total % 3600) / 60)
		return string.format("%d h %d min", h, m)
	end
	local d = math.floor(total / 86400)
	local h = math.floor((total % 86400) / 3600)
	if language == "de" then
		return string.format("%d T %d h", d, h)
	end
	return string.format("%d d %d h", d, h)
end

return Format
