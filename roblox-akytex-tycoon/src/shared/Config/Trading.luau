-- =====================================================================
--  AKYTEX TYCOON – Orders, Depot, Gewinn-Transfer, Liga, Strategie-Bots, Übungsaktie (Config.Trading)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §C14.2 (Trading), §B7.3, §B8, §B11.1, §C9;
--  MARKET.md §11–§13. Alle Geldwerte in CENT (100 = 1 AKY). Prozente als Bruch (0.06 = 6 %).
--  Wird an alle Clients repliziert (Order-Ticket zeigt Grenzen/Chips daraus) -> KEINE Geheimnisse hier!
--
--  Robux-Firewall (§0.4): nichts hier hängt von Pässen, Käufen oder Turm-Werten ab. Bot-Stufen und Plätze kommen
--  nur aus Lizenz + Know-how (ProgressionService.TradingPerks), der Bau-Kurs nur aus der Lizenz.
--
--  Abschnitte:
--    1) Gewinn-Transfer & Rettungsschirm      5) Strategie-Bots (4 Presets §B8.5)
--    2) Order-Ticket & Orders                  6) Tutorial-Übungsaktie ACAD (§B8.6)
--    3) Grenzen je Wert (Liquidität)           7) Feedback & Spam
--    4) Liga & Trader-XP-Regeln                8) Lizenz-Ersatztabelle (nur falls Config.Progression fehlt)
--  Validate(Config): { string }                prüft alle Zahlen (SelfTest / Boot-warn)
-- =====================================================================

local Trading = {}

-- ---------------------------------------------------------------------
-- 1) GEWINN-TRANSFER (AKY -> CR, §B8.2) & RETTUNGSSCHIRM (§B8.4)
--    Abhebbar = max(0, min(freies Cash, Depotwert − Basis, DayCapPct × Basis)), nur wenn Depotwert ≥ Threshold × Basis,
--    höchstens 1× je Börsentag. Den CR-Betrag rechnet der Turm (Bau-Kurs der Lizenz) – der Markt-Code kennt kein CR.
-- ---------------------------------------------------------------------
Trading.Transfer = {
	Threshold = 1.02, -- Depotwert muss mindestens 2 % über der Basis liegen
	DayCapPct = 0.06, -- höchstens 6 % der Basis je Börsentag
	MaxOfflineDays = 72, -- Auto-Transfer beim Offline-Abgleich: höchstens 72 verpasste Börsentage (= 24 h)
}
Trading.Refill = {
	Below = 0.5, -- Starthilfe nur, wenn Depotwert < 50 % der Basis und keine Position/Order offen
	To = 0.5, -- … füllt auf 50 % der Basis auf (1× je UTC-Tag, nie abhebbar)
}

-- ---------------------------------------------------------------------
-- 2) ORDER-TICKET & ORDERS (§B7.3, §C9 TradePlace, MARKET §11)
-- ---------------------------------------------------------------------
Trading.Protect = { Sl = 0.08, Tp = 0.15 } -- "Schutz an": Verlust-Stopp −8 % / Gewinn-Ziel +15 %
Trading.Chips = { 0.10, 0.25, "Max" } -- Betrags-Chips (Prozent vom Depotwert; Max = Klumpen-Grenze bzw. freies Geld)
Trading.ConfirmAbove = 0.20 -- Bestätigung "Sicher? Verteilen ist klüger." ab 20 % des Depotwerts in einem Wert
Trading.MinFeeCents = 100 -- Mindestgebühr 1 AKY je Ausführung
Trading.OrderLife = { DAY = true, H24 = 86400 } -- Laufzeit: bis Börsentag-Ende oder 24 h (Standard)
Trading.SeqWindow = 32 -- Doppelklick-Schutz: die letzten 32 Sequenznummern (rückt auch bei Ablehnung vor)
Trading.FatFinger = 0.5 -- Preise nur innerhalb Kurs × [0,5; 1,5]
Trading.TrailBps = { Min = 50, Max = 2000 } -- Nachzieh-Stopp-Abstand 0,5 % … 20 %
Trading.BuyStopReserve = 1.05 -- Kauf-Stopp reserviert Menge × Stopp × 1,05 + Gebühr (Kurslücken)
Trading.MaxOrdersHard = 50 -- absolute Obergrenze offener Orders je Spieler (§C16), Lizenz-Grenze darunter
Trading.MaxAlertsHard = 18 -- absolute Obergrenze Alarm-Linien (Know-how-Basis 3, +3 je Stufe)
Trading.Watch = { MaxLists = 5, MaxIds = 12 } -- Watchlists (Anzahl aus Know-how), je höchstens 12 Werte
Trading.TraderFrom = 4 -- ab Lizenz 4 (Trader I): Nachzieh-Stopp, Kauf-Stopp, Themen-Körbe
Trading.AlertBand = 0.5 -- Alarm-Linien innerhalb Kurs × [0,5; 1,5]

-- ---------------------------------------------------------------------
-- 3) GRENZEN JE WERT (MARKET §11.6): max. Positionswert = LiquidityBase × Positions-Faktor der Lizenz (×0,01 … ×100)
--    Werte in Cent: Stabil 5 Mio. AKY, Normal 2 Mio., Wild 0,5 Mio., ETF 20 Mio.
-- ---------------------------------------------------------------------
Trading.LiquidityBase = {
	Stabil = 500000000,
	Normal = 200000000,
	Wild = 50000000,
	ETF = 2000000000,
}

-- ---------------------------------------------------------------------
-- 4) LIGA & TRADER-XP-REGELN (§B8.7, §B9.1, §B11.1, MARKET §12.6)
--    Zählender Trade = Verkauf ≥ 2 % des Depotwerts nach ≥ 60 s Haltedauer (kein Bot, kein Admin-Fenster).
--    Zählender Börsentag = ≥ 3 zählende Trades. Teilnahme = ≥ 20 zählende Trades und ≥ 6 zählende Börsentage.
-- ---------------------------------------------------------------------
Trading.MinTradePct = 0.02
Trading.MinHoldSeconds = 60
Trading.ReadWellSeconds = 60 -- "Gut gelesen": Kauf ≤ 60 s nach einer Fakten-News in deren Richtung
Trading.QualifyingTrades = 3
Trading.MinNavStart = 100000 -- Börsentag zählt nur ab Start-Depotwert 1.000 AKY (MARKET §12.6)
Trading.League = {
	MinTrades = 20,
	MinDays = 6,
	MaxReturns = 504, -- höchstens so viele Börsentage je Woche (League.Returns)
	Tiers = { -- absolute Stufen nach Skill-Score (jeder kann eine erreichen)
		{ Key = "Bronze", Min = 300 },
		{ Key = "Silber", Min = 500 },
		{ Key = "Gold", Min = 700 },
		{ Key = "Diamant", Min = 850 },
	},
}

-- ---------------------------------------------------------------------
-- 5) STRATEGIE-BOTS (§B8.5) – handeln das Depot über dieselbe OrderEngine (Flag "Bot"), entscheiden 1× je Minute
--    auf 1m-Schlusskursen -> online = offline. Kapital je Bot nach Bot-Stufe (Know-how) 10/15/20/25/30 % des
--    Depotwerts, alle zusammen ≤ 30 %. Lohn 0,02 % des verwalteten Kapitals je Börsentag. Not-Aus je Bot,
--    Tagesverlust-Bremse −5 % (Bot pausiert bis zur nächsten Glocke).
--    Param: "CashPct" = Anteil des freien Geldes je Börsentag · "Capital" = Kapitalanteil (≤ Bot-Stufe) ·
--           "Drop" = Tagesrückgang, ab dem gekauft wird. Target: "ETF" = ETF-Id · "Inst" = Wert-Id · "None".
-- ---------------------------------------------------------------------
Trading.BotOrder = { "Sparplan", "Trend", "Dividend", "Dip" }
Trading.Bots = {
	Sparplan = {
		Name = { de = "Sparplan-Bot", en = "Savings plan bot" },
		Desc = {
			de = "Kauft jeden Börsentag ein ETF für einen festen Anteil deines freien Geldes.",
			en = "Buys an ETF every trading day for a fixed share of your free money.",
		},
		Licence = 3, -- ab Azubi III
		Param = "CashPct",
		Min = 0.05,
		Max = 0.20,
		Default = 0.10,
		Target = "ETF",
		DefaultTarget = 40, -- AKX36
	},
	Trend = {
		Name = { de = "Trend-Bot", en = "Trend bot" },
		Desc = {
			de = "Kauft, wenn SMA20 über SMA50 steigt (1m-Kerzen), verkauft beim Rückkreuzen, setzt ein Schutz-Paar.",
			en = "Buys when SMA20 crosses above SMA50 (1m candles), sells on the cross back, sets a safety pair.",
		},
		Licence = 4, -- ab Trader I
		Param = "Capital",
		Min = 0.05,
		Max = 0.30,
		Default = 0.10,
		Target = "Inst",
		Fast = 20,
		Slow = 50,
	},
	Dividend = {
		Name = { de = "Dividenden-Bot", en = "Dividend bot" },
		Desc = {
			de = "Hält die 6 Zahler mit der höchsten Dividende gleich gewichtet und gleicht jeden Börsentag aus.",
			en = "Holds the 6 highest-yield payers equally weighted and rebalances every trading day.",
		},
		Licence = 6, -- ab Trader III
		Param = "Capital",
		Min = 0.05,
		Max = 0.30,
		Default = 0.10,
		Target = "None",
		Count = 6,
		Rebalance = 0.10, -- erst ab 10 % Abweichung vom Zielgewicht handeln (spart Gebühren)
	},
	Dip = {
		Name = { de = "Dip-Käufer", en = "Dip buyer" },
		Desc = {
			de = "Kauft einen Wert deiner Watchlist nach einem Tagesrückgang, immer mit Verlust-Stopp.",
			en = "Buys a watchlist stock after a daily drop, always with a loss stop.",
		},
		Licence = 7, -- ab Fondsmanager I
		Param = "Drop",
		Min = 0.03,
		Max = 0.08,
		Default = 0.05,
		Target = "None",
		Slots = 3, -- höchstens 3 gleichzeitige Dip-Positionen (je ein Drittel des Bot-Kapitals)
		Stop = 0.08, -- automatischer Verlust-Stopp −8 %
	},
}
Trading.BotCapital = { 0.10, 0.15, 0.20, 0.25, 0.30 } -- Bot-Stufe 0 … 4 (Know-how-Knoten BotLvl.<Preset>)
Trading.BotTotalPct = 0.30
Trading.BotWageBps = 2 -- 0,02 % des verwalteten Kapitals je Börsentag (AKY-Senke)
Trading.BotDayStop = -0.05
Trading.BotMinOrderCents = 10000 -- Bots handeln nie unter 100 AKY je Order (Gebühren-Schutz)
Trading.OfflineBotHours = 12
Trading.OfflineOrderHours = 24

-- ---------------------------------------------------------------------
-- 6) TUTORIAL-ÜBUNGSAKTIE ACAD (Id 250, §B8.6) – Kurs pro Spieler, nie im Frame, nur per Replay-Remote (1 Hz)
--    100,00 AKY -> News bei t0 + 2 s -> 8 s Lesefenster -> +15 % über 45 s (Smoothstep) -> flach.
--    Kauf nur mit Chip 10 %. Nach 90 s automatischer Verkauf bei +12 %. Einmal je Konto (Flags.TutorialTrade).
-- ---------------------------------------------------------------------
Trading.Tutorial = {
	InstId = 250,
	Start = 10000, -- Cent
	NewsAt = 2,
	ReadSeconds = 8,
	Jump = 0.15,
	Ramp = 45,
	AutoSellAfter = 90,
	AutoSellAt = 0.12,
	Chip = 0.10,
	Timeout = 240, -- danach endet der Übungs-Stream (neu starten möglich, solange nicht abgeschlossen)
	Wiggle = 0.0015, -- kleines, festes Zittern (Sinus, kein Zufall), damit der Chart lebt
}

-- ---------------------------------------------------------------------
-- 7) FEEDBACK & SPAM (§B7.6, MARKET §13)
-- ---------------------------------------------------------------------
Trading.LossStreakWarn = { Trades = 10, Seconds = 120 } -- Tiko-Hinweis + 30-s-Abkühl-Tipp (keine Sperre)
Trading.SpamPerMinute = 50 -- mehr Order-Anfragen pro Minute -> AntiCheat-Hinweis (keine Strafe)

-- ---------------------------------------------------------------------
-- 8) LIZENZ-ERSATZTABELLE (§B9.2) – gilt NUR, wenn Config.Progression.Licences fehlt (Studio-Teiltest).
--    Die echte Tabelle (eine für WP4/WP6/WP9) steht in Config.Progression. Basis in Cent, Gebühr in Basispunkten.
-- ---------------------------------------------------------------------
-- stylua: ignore start
Trading.LicenceFallback = {
	{ Key = "Azubi1",   Basis = 2500000,    BauKurs = 40,    FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  BotSlots = 0 },
	{ Key = "Azubi2",   Basis = 5000000,    BauKurs = 200,   FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  BotSlots = 0 },
	{ Key = "Azubi3",   Basis = 10000000,   BauKurs = 800,   FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  BotSlots = 1 },
	{ Key = "Trader1",  Basis = 25000000,   BauKurs = 1500,  FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", BotSlots = 2 },
	{ Key = "Trader2",  Basis = 60000000,   BauKurs = 3000,  FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", BotSlots = 2 },
	{ Key = "Trader3",  Basis = 150000000,  BauKurs = 6000,  FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", BotSlots = 3 },
	{ Key = "Fonds1",   Basis = 400000000,  BauKurs = 12000, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  BotSlots = 4 },
	{ Key = "Fonds2",   Basis = 1000000000, BauKurs = 20000, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  BotSlots = 4 },
	{ Key = "Fonds3",   Basis = 2500000000, BauKurs = 30000, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  BotSlots = 4 },
	{ Key = "Legende",  Basis = 6000000000, BauKurs = 40000, FeeBps = 3,  MaxWeight = 0.60, MaxOrders = 50, PosFactor = 100,  Layer = "Pro",    Set = "Fonds",  BotSlots = 5 },
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- ---------------------------------------------------------------------
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Trading.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Trading." .. text)
	end
	local function frac(path: string, v: any, lo: number, hi: number)
		if not isNum(v) or v < lo or v > hi then
			add(("%s: Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	local function intMin(path: string, v: any, lo: number)
		if not isNum(v) or v % 1 ~= 0 or v < lo then
			add(("%s: ganze Zahl ≥ %s erwartet"):format(path, tostring(lo)))
		end
	end

	frac("Transfer.Threshold", Trading.Transfer.Threshold, 1, 2)
	frac("Transfer.DayCapPct", Trading.Transfer.DayCapPct, 0, 1)
	intMin("Transfer.MaxOfflineDays", Trading.Transfer.MaxOfflineDays, 0)
	frac("Refill.Below", Trading.Refill.Below, 0, 1)
	frac("Refill.To", Trading.Refill.To, 0, 1)
	if
		isNum(Trading.Refill.To)
		and isNum(Trading.Transfer.Threshold)
		and Trading.Refill.To >= Trading.Transfer.Threshold
	then
		add("Refill.To: muss unter Transfer.Threshold liegen (Starthilfe nie abhebbar)")
	end
	frac("Protect.Sl", Trading.Protect.Sl, 0.01, 0.5)
	frac("Protect.Tp", Trading.Protect.Tp, 0.01, 1)
	if type(Trading.Chips) ~= "table" or #Trading.Chips ~= 3 or Trading.Chips[3] ~= "Max" then
		add('Chips: { 0.10, 0.25, "Max" } erwartet')
	else
		frac("Chips[1]", Trading.Chips[1], 0.01, 0.5)
		frac("Chips[2]", Trading.Chips[2], 0.01, 0.5)
	end
	frac("ConfirmAbove", Trading.ConfirmAbove, 0, 1)
	intMin("MinFeeCents", Trading.MinFeeCents, 0)
	if Trading.OrderLife.DAY ~= true then
		add("OrderLife.DAY: true erwartet")
	end
	intMin("OrderLife.H24", Trading.OrderLife.H24, 60)
	if isNum(Trading.OrderLife.H24) and Trading.OrderLife.H24 > Trading.OfflineOrderHours * 3600 then
		add("OrderLife.H24: darf nicht länger als OfflineOrderHours sein (Offline-Abgleich)")
	end
	intMin("SeqWindow", Trading.SeqWindow, 4)
	frac("FatFinger", Trading.FatFinger, 0.05, 0.9)
	intMin("TrailBps.Min", Trading.TrailBps.Min, 1)
	intMin("TrailBps.Max", Trading.TrailBps.Max, 1)
	if isNum(Trading.TrailBps.Min) and isNum(Trading.TrailBps.Max) and Trading.TrailBps.Min > Trading.TrailBps.Max then
		add("TrailBps: Min ≤ Max erwartet")
	end
	frac("BuyStopReserve", Trading.BuyStopReserve, 1, 2)
	intMin("MaxOrdersHard", Trading.MaxOrdersHard, 1)
	if isNum(Trading.MaxOrdersHard) and Trading.MaxOrdersHard > 50 then
		add("MaxOrdersHard: höchstens 50 (§C16)")
	end
	intMin("MaxAlertsHard", Trading.MaxAlertsHard, 1)
	if isNum(Trading.MaxAlertsHard) and Trading.MaxAlertsHard > 18 then
		add("MaxAlertsHard: höchstens 18 (§C16)")
	end
	intMin("Watch.MaxLists", Trading.Watch.MaxLists, 1)
	intMin("Watch.MaxIds", Trading.Watch.MaxIds, 1)
	intMin("TraderFrom", Trading.TraderFrom, 1)
	frac("AlertBand", Trading.AlertBand, 0.05, 0.95)
	for _, class in ipairs({ "Stabil", "Normal", "Wild", "ETF" }) do
		intMin("LiquidityBase." .. class, (Trading.LiquidityBase :: any)[class], 1)
	end
	frac("MinTradePct", Trading.MinTradePct, 0, 1)
	intMin("MinHoldSeconds", Trading.MinHoldSeconds, 0)
	intMin("ReadWellSeconds", Trading.ReadWellSeconds, 1)
	intMin("QualifyingTrades", Trading.QualifyingTrades, 1)
	intMin("MinNavStart", Trading.MinNavStart, 0)
	intMin("League.MinTrades", Trading.League.MinTrades, 0)
	intMin("League.MinDays", Trading.League.MinDays, 0)
	intMin("League.MaxReturns", Trading.League.MaxReturns, 1)
	local lastMin = -1
	for i, tier in ipairs(Trading.League.Tiers) do
		if type(tier.Key) ~= "string" or not isNum(tier.Min) or tier.Min <= lastMin or tier.Min > 1000 then
			add(("League.Tiers[%d]: Key + aufsteigendes Min (0–1000) erwartet"):format(i))
		else
			lastMin = tier.Min
		end
	end
	local seen: { [string]: boolean } = {}
	for _, key in ipairs(Trading.BotOrder) do
		local preset = (Trading.Bots :: any)[key]
		if type(preset) ~= "table" then
			add("Bots." .. tostring(key) .. ": fehlt")
			continue
		end
		assert(not seen[key], "[Config.Trading] doppelter Bot " .. tostring(key))
		seen[key] = true
		intMin("Bots." .. key .. ".Licence", preset.Licence, 1)
		frac("Bots." .. key .. ".Min", preset.Min, 0, 1)
		frac("Bots." .. key .. ".Max", preset.Max, 0, 1)
		frac("Bots." .. key .. ".Default", preset.Default, 0, 1)
		if isNum(preset.Min) and isNum(preset.Max) and isNum(preset.Default) then
			if preset.Min > preset.Default or preset.Default > preset.Max then
				add("Bots." .. key .. ": Min ≤ Default ≤ Max erwartet")
			end
		end
		if preset.Param ~= "CashPct" and preset.Param ~= "Capital" and preset.Param ~= "Drop" then
			add("Bots." .. key .. ".Param: CashPct/Capital/Drop erwartet")
		end
		if preset.Target ~= "ETF" and preset.Target ~= "Inst" and preset.Target ~= "None" then
			add("Bots." .. key .. ".Target: ETF/Inst/None erwartet")
		end
		if type(preset.Name) ~= "table" or type(preset.Name.de) ~= "string" or type(preset.Name.en) ~= "string" then
			add("Bots." .. key .. ".Name: { de, en } erwartet")
		end
	end
	for key in pairs(Trading.Bots) do
		if not seen[key] then
			add("Bots." .. tostring(key) .. ": fehlt in BotOrder")
		end
	end
	if isNum(Trading.Bots.Trend.Fast) and isNum(Trading.Bots.Trend.Slow) then
		if Trading.Bots.Trend.Fast < 2 or Trading.Bots.Trend.Fast >= Trading.Bots.Trend.Slow then
			add("Bots.Trend: 2 ≤ Fast < Slow erwartet")
		end
	else
		add("Bots.Trend.Fast/Slow: Zahlen erwartet")
	end
	intMin("Bots.Dividend.Count", Trading.Bots.Dividend.Count, 1)
	intMin("Bots.Dip.Slots", Trading.Bots.Dip.Slots, 1)
	frac("Bots.Dip.Stop", Trading.Bots.Dip.Stop, 0.01, 0.5)
	if #Trading.BotCapital ~= 5 then
		add("BotCapital: 5 Stufen erwartet")
	end
	for i, pct in ipairs(Trading.BotCapital) do
		frac(("BotCapital[%d]"):format(i), pct, 0, 1)
		if isNum(pct) and isNum(Trading.BotTotalPct) and pct > Trading.BotTotalPct then
			add(("BotCapital[%d]: höher als BotTotalPct"):format(i))
		end
	end
	frac("BotTotalPct", Trading.BotTotalPct, 0, 1)
	frac("BotWageBps", Trading.BotWageBps, 0, 100)
	frac("BotDayStop", Trading.BotDayStop, -1, 0)
	intMin("BotMinOrderCents", Trading.BotMinOrderCents, 0)
	frac("OfflineBotHours", Trading.OfflineBotHours, 0, 24)
	frac("OfflineOrderHours", Trading.OfflineOrderHours, 1, 24)
	local tut = Trading.Tutorial
	intMin("Tutorial.InstId", tut.InstId, 1)
	intMin("Tutorial.Start", tut.Start, 100)
	intMin("Tutorial.NewsAt", tut.NewsAt, 0)
	intMin("Tutorial.ReadSeconds", tut.ReadSeconds, 0)
	frac("Tutorial.Jump", tut.Jump, 0, 1)
	intMin("Tutorial.Ramp", tut.Ramp, 1)
	intMin("Tutorial.AutoSellAfter", tut.AutoSellAfter, 1)
	frac("Tutorial.AutoSellAt", tut.AutoSellAt, 0, 1)
	frac("Tutorial.Chip", tut.Chip, 0.01, 0.3)
	intMin("Tutorial.Timeout", tut.Timeout, 30)
	frac("Tutorial.Wiggle", tut.Wiggle, 0, 0.01)
	if isNum(tut.Timeout) and isNum(tut.AutoSellAfter) and tut.Timeout <= tut.AutoSellAfter then
		add("Tutorial.Timeout: muss länger als AutoSellAfter sein")
	end
	intMin("LossStreakWarn.Trades", Trading.LossStreakWarn.Trades, 1)
	intMin("LossStreakWarn.Seconds", Trading.LossStreakWarn.Seconds, 1)
	intMin("SpamPerMinute", Trading.SpamPerMinute, 1)
	if #Trading.LicenceFallback ~= 10 then
		add("LicenceFallback: 10 Lizenzen erwartet")
	end
	local lastBasis = 0
	for i, lic in ipairs(Trading.LicenceFallback) do
		local where = ("LicenceFallback[%d]"):format(i)
		intMin(where .. ".Basis", lic.Basis, 1)
		if isNum(lic.Basis) and lic.Basis <= lastBasis then
			add(where .. ".Basis: muss mit der Lizenz steigen")
		end
		lastBasis = if isNum(lic.Basis) then lic.Basis else lastBasis
		frac(where .. ".FeeBps", lic.FeeBps, 0, 100)
		frac(where .. ".MaxWeight", lic.MaxWeight, 0.05, 1)
		intMin(where .. ".MaxOrders", lic.MaxOrders, 1)
		frac(where .. ".PosFactor", lic.PosFactor, 0, 1000)
		intMin(where .. ".BotSlots", lic.BotSlots, 0)
		if lic.Set ~= "Azubi" and lic.Set ~= "Trader" and lic.Set ~= "Fonds" then
			add(where .. ".Set: Azubi/Trader/Fonds erwartet")
		end
	end
	return errors
end

return Trading
