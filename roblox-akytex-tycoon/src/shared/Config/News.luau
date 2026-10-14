-- =====================================================================
--  AKYTEX TYCOON – Schlagzeilen-Vorlagen der Markt-Engine (Config.News)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §C14.2 ("Vorlagen-Schlüssel je Art mit Parametern"), §C15, §B7.4;
--  MARKET.md §6.2. Die Texte selbst stehen DE/EN in Shared/Lang/News.luau (Präfix "news.").
--
--  So funktioniert eine News (Types.NewsItem): der Server schickt NUR Schlüssel + Parameter, der CLIENT lokalisiert.
--    Key  = einer der Schlüssel unten          Args = { name = "Cognivo KI", band = "news.band.2", … }
--    Platzhalter im Text: {name} {band} {amt} {stars} {buyer} {product} {sector} {cons} {min} {secs}
--    Ersetzen (Client, z. B. NewsFeed):  text = Lang.T(lang, item.Key)
--      text = text:gsub("{(%a+)}", function(k) local v = item.Args[k]
--        if type(v) == "string" and Lang.Has(v) then return Lang.T(lang, v) end; return tostring(v or "") end)
--    -> Werte, die selbst "news."-Schlüssel sind (band, sector, product, cons), werden ebenfalls übersetzt.
--    {band} ist das Stärke-Wort (fett anzeigen), NewsItem.Band = 1…4, Stars = 1…3 bei Gerüchten,
--    Dir = +1/−1 = Ton der Schlagzeile (bei Fakt/Bestätigung/Dementi/Zahlen = echte Kursrichtung).
--    Admin-Eilmeldung: Key "news.admin", der gefilterte Text steht in NewsItem.Text { de, en }.
--  Wortliste §0.7 beachten (keine Glücksspiel-/Hebel-/Krypto-Wörter, kein "garantiert").
--
--  Inhalt: Fact/Rumor/AsExpected { Up, Down } · Confirm · Deny · Sector · Theme · Macro · Earnings · Dividend · Warn ·
--          Crash · Rally · Weekly · Ipo · Admin · Halt · Resume · Bands · Sectors · Products · Cons · Stars · Validate
-- =====================================================================

local News = {}

-- ---------------------------------------------------------------------
-- 1) FIRMEN-NEWS (Fakt 55 % · Gerücht 25 % · "wie erwartet" 20 %)
-- ---------------------------------------------------------------------
News.Fact = {
	Up = {
		"news.fact.up.contract", -- {name} {amt} {band}
		"news.fact.up.product", -- {name} {product} {band}
		"news.fact.up.partner", -- {name} {buyer} {band}
		"news.fact.up.sales",
		"news.fact.up.expansion",
		"news.fact.up.award",
		"news.fact.up.record",
		"news.fact.up.patent", -- {product}
		"news.fact.up.customers",
	},
	Down = {
		"news.fact.down.recall",
		"news.fact.down.outage",
		"news.fact.down.delay", -- {product}
		"news.fact.down.lostdeal", -- {buyer}
		"news.fact.down.fine",
		"news.fact.down.supply",
		"news.fact.down.hack",
		"news.fact.down.strike",
		"news.fact.down.costs",
	},
}
News.Rumor = { -- immer mit {stars}
	Up = { "news.rumor.up.takeover", "news.rumor.up.deal", "news.rumor.up.product", "news.rumor.up.partner" },
	Down = { "news.rumor.down.ceo", "news.rumor.down.problems", "news.rumor.down.probe", "news.rumor.down.delay" },
}
News.AsExpected = { -- klingt gut (Up) bzw. schlecht (Down) – der Kurs reagiert umgekehrt ("sell the news")
	Up = { "news.expected.up.profit", "news.expected.up.sales", "news.expected.up.outlook" },
	Down = { "news.expected.down.profit", "news.expected.down.sales", "news.expected.down.outlook" },
}
News.Confirm = "news.confirm"
News.Deny = "news.deny"

-- ---------------------------------------------------------------------
-- 2) SEKTOR, THEMEN, MAKRO
-- ---------------------------------------------------------------------
News.Sector = { Up = "news.sector.up", Down = "news.sector.down" } -- {sector} {band}
News.Theme = {
	Ai = "news.theme.Ai",
	Chips = "news.theme.Chips",
	Heat = "news.theme.Heat",
	Esport = "news.theme.Esport",
	Space = "news.theme.Space",
}
News.Macro = {
	Rates = {
		Preview = "news.macro.Rates.preview", -- {cons}
		Higher = "news.macro.Rates.higher", -- {band}
		Lower = "news.macro.Rates.lower",
		AsExpected = "news.macro.Rates.expected",
	},
	Growth = {
		Preview = "news.macro.Growth.preview",
		Higher = "news.macro.Growth.higher",
		Lower = "news.macro.Growth.lower",
		AsExpected = "news.macro.Growth.expected",
	},
	Energy = {
		Preview = "news.macro.Energy.preview",
		Higher = "news.macro.Energy.higher",
		Lower = "news.macro.Energy.lower",
		AsExpected = "news.macro.Energy.expected",
	},
}

-- ---------------------------------------------------------------------
-- 3) QUARTALSZAHLEN, DIVIDENDEN
-- ---------------------------------------------------------------------
News.Earnings = {
	Preview = "news.earn.preview", -- {name} {min} {cons}
	Beat = "news.earn.beat", -- {name} {band}
	Miss = "news.earn.miss",
	Inline = "news.earn.inline",
}
News.Dividend = "news.div" -- {name} {amt} (AKY je Aktie)

-- ---------------------------------------------------------------------
-- 4) CRASH, RALLYE, WOCHEN-TERMINE
-- ---------------------------------------------------------------------
News.Warn = {
	Crash = { "news.warn.crash.1", "news.warn.crash.2", "news.warn.crash.3" },
	Rally = { "news.warn.rally.1", "news.warn.rally.2", "news.warn.rally.3" },
	Sector = "news.warn.sector", -- {sector}
}
News.Crash = { All = "news.crash.all", Sector = "news.crash.sector", Inst = "news.crash.inst" } -- {band} {sector}/{name}
News.Rally = { All = "news.rally.all", Sector = "news.rally.sector", Inst = "news.rally.inst" }
News.Weekly = {
	CrashFriday = "news.weekly.CrashFriday",
	RallyWednesday = "news.weekly.RallyWednesday",
	AutoShow = "news.weekly.AutoShow",
}

-- ---------------------------------------------------------------------
-- 5) IPO, ADMIN, HANDELSPAUSEN
-- ---------------------------------------------------------------------
News.Ipo = {
	Prospect = "news.ipo.prospect", -- {name} {sector}
	Listing = "news.ipo.listing", -- {name} {secs}
	OpenUp = "news.ipo.open.up", -- {name} {band}
	OpenDown = "news.ipo.open.down",
}
News.Admin = "news.admin" -- Admin-Eilmeldung (Text in NewsItem.Text)
News.AdminMove = {
	Crash = "news.admin.crash",
	Rally = "news.admin.rally",
	Pump = "news.admin.pump", -- {name}
	Dump = "news.admin.dump",
	Vol = "news.admin.vol",
	Normalize = "news.admin.normalize",
}
News.Halt = { All = "news.halt.all", Inst = "news.halt.inst" } -- {secs} ({name})
News.Resume = { All = "news.resume.all", Inst = "news.resume.inst" }

-- ---------------------------------------------------------------------
-- 6) BAUSTEINE (Parameter-Werte, die der Client übersetzt)
-- ---------------------------------------------------------------------
News.Bands = { "news.band.1", "news.band.2", "news.band.3", "news.band.4" } -- leicht · deutlich · massiv · historisch
News.Sectors = {
	T = "news.sec.T",
	E = "news.sec.E",
	M = "news.sec.M",
	K = "news.sec.K",
	G = "news.sec.G",
	F = "news.sec.F",
}
News.Products = {
	T = { "news.product.T.1", "news.product.T.2", "news.product.T.3" },
	E = { "news.product.E.1", "news.product.E.2", "news.product.E.3" },
	M = { "news.product.M.1", "news.product.M.2", "news.product.M.3" },
	K = { "news.product.K.1", "news.product.K.2", "news.product.K.3" },
	G = { "news.product.G.1", "news.product.G.2", "news.product.G.3" },
	F = { "news.product.F.1", "news.product.F.2", "news.product.F.3" },
}
News.Cons = { Up = "news.cons.up", Down = "news.cons.down", Flat = "news.cons.flat" }
News.Stars = { "★", "★★", "★★★" }

-- ---------------------------------------------------------------------
-- PRÜFUNG: jeder Schlüssel ist ein "news."-Schlüssel (dass er in Lang existiert, prüfen SelfTest/Vertrags-Prüfer)
-- ---------------------------------------------------------------------
local MAX_DEPTH = 4

function News.Validate(_config: any): { string }
	local errors: { string } = {}
	local count = 0
	local function walk(path: string, value: any, depth: number)
		if depth > MAX_DEPTH then
			return
		end
		if type(value) == "string" then
			if path ~= "Stars" and string.sub(path, 1, 5) ~= "Stars" then
				count += 1
				if string.sub(value, 1, 5) ~= "news." then
					table.insert(
						errors,
						("Config.News.%s: Schlüssel mit Präfix news. erwartet (%s)"):format(path, value)
					)
				end
			end
		elseif type(value) == "table" then
			for key, child in pairs(value) do
				walk(if path == "" then tostring(key) else path .. "." .. tostring(key), child, depth + 1)
			end
		end
	end
	for key, value in pairs(News) do
		if type(value) ~= "function" and key ~= "Stars" then
			walk(key, value, 1)
		end
	end
	if #News.Fact.Up == 0 or #News.Fact.Down == 0 or #News.Rumor.Up == 0 or #News.Rumor.Down == 0 then
		table.insert(errors, "Config.News: Fact/Rumor brauchen je mindestens eine Vorlage Up und Down")
	end
	if #News.AsExpected.Up == 0 or #News.AsExpected.Down == 0 then
		table.insert(errors, "Config.News: AsExpected braucht je mindestens eine Vorlage Up und Down")
	end
	if #News.Bands ~= 4 or #News.Stars ~= 3 then
		table.insert(errors, "Config.News: 4 Bänder und 3 Sterne-Stufen erwartet")
	end
	if count == 0 then
		table.insert(errors, "Config.News: keine Vorlagen gefunden")
	end
	return errors
end

return News
