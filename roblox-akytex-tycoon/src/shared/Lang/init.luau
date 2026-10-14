-- =====================================================================
--  AKYTEX TYCOON – Sprachen DE/EN (Shared/Lang)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C15 + §C6.1 (CC-Kopie 1:1, nur FILES neu).
--
--  Domänen-Dateien (jedes Paket pflegt seine, Präfix-Pflicht; gleiche Liste = LANG_PREFIX in contract_check.py):
--    Core core. (WP1) · Ui ui. (WP2) · Market mkt. · News news. (WP3) · Trade trade. (WP4) · Terminal term. (WP5) ·
--    Tower tower. (WP6) · TowerUi tui. · Life life. (WP8) · World world. · Vehicle car. (WP7) ·
--    Progress prog. · Tutorial tut. · Social soc. (WP9) · Shop shop./item. (WP10) · Admin admin. · Events evt. (WP11) ·
--    Team admin. (W19 Team-Rollen, Chat-Befehle, Banns – gleiches Präfix wie Admin, Schlüssel nie doppelt)
--  Jede Datei gibt { de = { [key] = text }, en = { [key] = text } } zurück. Doppelte Schlüssel -> warn.
--
--  Öffentliche API:
--    Lang.T(lang, key, ...): string      string.format(text, ...) in pcall; fehlt der Schlüssel -> Englisch -> Schlüssel
--    Lang.Pick(lang, { de, en }): string Config-Anzeigenamen
--    Lang.For(p, override?): "de" | "en" override "de"/"en" aus Einstellungen, sonst LocaleId "de…" -> "de", sonst "en"
--    Lang.Missing(): { string }          Schlüssel, die in einer Sprache fehlen (+ fehlende/kaputte Dateien)
--    Lang.Has(key): boolean
-- =====================================================================

local RunService = game:GetService("RunService")

local Types = require(script.Parent:WaitForChild("Types"))

local Lang = {}

local LANGUAGES: { Types.Lang } = { "de", "en" }
local MAX_ARGS = 16

local FILES: { { Name: string, Prefixes: { string } } } = {
	{ Name = "Core", Prefixes = { "core." } },
	{ Name = "Ui", Prefixes = { "ui." } },
	{ Name = "Market", Prefixes = { "mkt." } },
	{ Name = "News", Prefixes = { "news." } },
	{ Name = "Trade", Prefixes = { "trade." } },
	{ Name = "Terminal", Prefixes = { "term." } },
	{ Name = "Tower", Prefixes = { "tower." } },
	{ Name = "TowerUi", Prefixes = { "tui." } },
	{ Name = "World", Prefixes = { "world." } },
	{ Name = "Vehicle", Prefixes = { "car." } },
	{ Name = "Life", Prefixes = { "life." } },
	{ Name = "Progress", Prefixes = { "prog." } },
	{ Name = "Tutorial", Prefixes = { "tut." } },
	{ Name = "Social", Prefixes = { "soc." } },
	{ Name = "Shop", Prefixes = { "shop.", "item." } },
	{ Name = "Admin", Prefixes = { "admin." } },
	{ Name = "Team", Prefixes = { "admin." } },
	{ Name = "Events", Prefixes = { "evt." } },
}

local dict: { [string]: { [string]: string } } = { de = {}, en = {} }
local sourceOf: { [string]: { [string]: string } } = { de = {}, en = {} } -- Schlüssel -> Datei (für Doppelte)
local loadIssues: { string } = {}

-- Client: erst warten, bis die erste Replikation fertig ist (sonst fehlen Dateien evtl. noch)
if RunService:IsClient() and not RunService:IsServer() and not game:IsLoaded() then
	game.Loaded:Wait()
end

local function hasPrefix(key: string, prefixes: { string }): boolean
	for _, prefix in ipairs(prefixes) do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function loadFile(name: string, prefixes: { string })
	local module = script:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		table.insert(loadIssues, "Lang." .. name .. " (Datei fehlt)")
		return
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		table.insert(loadIssues, "Lang." .. name .. " (Fehler beim Laden)")
		warn("[Lang] Lang." .. name .. " konnte nicht geladen werden: " .. tostring(result))
		return
	end
	for _, lang in ipairs(LANGUAGES) do
		local entries = result[lang]
		if type(entries) ~= "table" then
			table.insert(loadIssues, ("Lang.%s.%s (Tabelle fehlt)"):format(name, lang))
			continue
		end
		local target, sources = dict[lang], sourceOf[lang]
		for key, text in pairs(entries) do
			if type(key) ~= "string" or type(text) ~= "string" then
				warn(
					("[Lang] Lang.%s.%s: Schlüssel und Text müssen Strings sein (%s)"):format(
						name,
						lang,
						tostring(key)
					)
				)
			elseif sources[key] ~= nil then
				warn(
					("[Lang] Doppelter Schlüssel %s (%s) in Lang.%s, schon in Lang.%s"):format(
						key,
						lang,
						name,
						sources[key]
					)
				)
			else
				if not hasPrefix(key, prefixes) then
					warn(
						("[Lang] Lang.%s: Schlüssel %s hat das falsche Präfix (erwartet %s)"):format(
							name,
							key,
							table.concat(prefixes, " / ")
						)
					)
				end
				target[key] = text
				sources[key] = name
			end
		end
	end
end

for _, file in ipairs(FILES) do
	loadFile(file.Name, file.Prefixes)
end

-- Text in der gewünschten Sprache; fehlt er -> Englisch -> der Schlüssel selbst.
-- Argumente wie string.format (%d, %s, …). Kaputtes Format -> Text ohne Ersetzung.
function Lang.T(lang: Types.Lang, key: string, ...: any): string
	local name = if type(key) == "string" then key else tostring(key)
	local entries = dict[lang]
	local text = (entries and entries[name]) or dict.en[name] or name
	local count = select("#", ...)
	if count == 0 and not string.find(text, "%", 1, true) then
		return text
	end
	-- nil/Tabellen/Instanzen sicher in Text verwandeln (string.format würde sonst scheitern)
	local args = table.create(math.min(count, MAX_ARGS))
	for i = 1, math.min(count, MAX_ARGS) do
		local value = select(i, ...)
		local kind = type(value)
		if kind == "number" then
			args[i] = if value == value then value else 0
		elseif kind == "string" then
			args[i] = value
		elseif value == nil then
			args[i] = ""
		else
			args[i] = tostring(value)
		end
	end
	local ok, result = pcall(string.format, text, table.unpack(args, 1, math.min(count, MAX_ARGS)))
	if ok then
		return result
	end
	return text
end

-- { de = "…", en = "…" } -> Text in der Sprache (Fallback Englisch, dann Deutsch)
function Lang.Pick(lang: Types.Lang, t: { de: string, en: string }): string
	local raw: any = t
	if type(raw) == "string" then
		return raw
	elseif type(raw) ~= "table" then
		return ""
	end
	local value = raw[lang]
	if type(value) ~= "string" then
		value = raw.en
	end
	if type(value) ~= "string" then
		value = raw.de
	end
	return if type(value) == "string" then value else ""
end

-- Sprache eines Spielers: Einstellung "de"/"en" gewinnt, sonst LocaleId ("de-de" -> "de"), sonst "en"
function Lang.For(p: Player, override: string?): Types.Lang
	if override == "de" or override == "en" then
		return override
	end
	local ok, locale = pcall(function()
		return p.LocaleId
	end)
	if ok and type(locale) == "string" and string.lower(string.sub(locale, 1, 2)) == "de" then
		return "de"
	end
	return "en"
end

function Lang.Has(key: string): boolean
	return dict.en[key] ~= nil or dict.de[key] ~= nil
end

-- Schlüssel, die in einer Sprache fehlen (sortiert) + fehlende/kaputte Dateien. Leer = alles ok.
function Lang.Missing(): { string }
	local missing: { string } = {}
	for _, lang in ipairs(LANGUAGES) do
		for _, other in ipairs(LANGUAGES) do
			if other ~= lang then
				for key in pairs(dict[other]) do
					if dict[lang][key] == nil then
						table.insert(missing, ("%s (fehlt in %s)"):format(key, lang))
					end
				end
			end
		end
	end
	table.sort(missing)
	for _, issue in ipairs(loadIssues) do
		table.insert(missing, issue)
	end
	return missing
end

return Lang
