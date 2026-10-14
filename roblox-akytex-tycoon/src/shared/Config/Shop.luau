-- =====================================================================
--  AKYTEX TYCOON – SHOP, ROBUX, CR-KONTO (Config.Shop)
--  Besitzer: WP10 (Monetarisierung, Shop, CR-Konto). Vertrag: DESIGN.md §B14 (14 Pässe, 17 Produkte, Abo, Angebots-
--  Regeln, Firewall & Policy), §0.4/§0.8 (Robux-Firewall, harte Leitplanken), §C14.2 (Shop), §C5.9, §C11.4.
--
--  GAMEPÄSSE, PRODUKTE, ABO: "Id = 0" (Abo: Id = "") heißt "noch nicht eingerichtet" -> der Shop zeigt "Bald verfügbar".
--  Wenn du sie im Creator Dashboard angelegt hast, trag hier die Ids ein (sonst nichts ändern). Preise im Dashboard
--  setzen – der Shop zeigt IMMER den Live-Preis aus dem Marktplatz (Price hier = nur Planwert für Prüfungen/Doku).
--
--  HARTE REGEL (Robux-Firewall §0.4): Robux geben NUR Turm-Seite (CR, Boosts, Bau-Express, Kosmetik, Komfort im Turm,
--  Saison-Premium/-Stufen). NIE AKY, Aktien, Orders, Lizenz, Trader-XP, Know-how, Ruf, Aktien-Sterne, Strategie-Bots,
--  Alarme, Watchlists, Layouts, Marktinfos. Shop.Validate meldet jeden Verstoß, ShopService streicht ForbiddenRobuxFields
--  aus jeder Robux-Gewährung, und der SelfTest "Firewall" prüft das Depot byte-gleich.
--  KEINE bezahlten Zufallsartikel (RandomItemsEnabled = false, kein Random/Odds/Weights – SelfTest "NoPaidRandom").
--
--  Reines Daten-Modul (lädt keine Roblox-Dienste/-Typen) -> mit der Luau-CLI ladbar.
--  Öffentliche Helfer:
--    Shop.PassesByKey[key] · Shop.PassesById[id] (nur Id ~= 0) · Shop.ProductsByKey[key] · Shop.ProductsById[id]
--    Shop.IsKnown(key): boolean                    Pass, Produkt oder "Club"
--    Shop.BundleValue(passKey): number              Summe der Planpreise der enthaltenen Pässe (0 = kein Paket)
--    Shop.BundleDiscountPct(passKey, value?, price?): number   echter Rabatt in ganzen Prozent (aus Live-Preisen)
--    Shop.VoucherCredits(product, steadyPerSec): number        CR eines Bau-Gutscheins (mind. Min, ≤ 9e15)
--    Shop.SanitizeGrant(grant, robux): (Grant, { string })     Kopie; robux = true streicht ForbiddenRobuxFields
--    Shop.ParseUtc("2026-10-12T00:00:00Z"): number?             Sekunden seit 1970 (UTC)
--    Shop.SeasonIdAt(seasonConfig, now): number                 aktive Saison (inkl. Rolling-Regel aus Config.Season)
--    Shop.Validate(Config): { string }
-- =====================================================================

local Shop = {}

local MAX_MONEY = 9e15

-- ---------------------------------------------------------------------
-- 1) GAMEPÄSSE (14, dauerhaft, §B14.1) – Wirkung setzen die Besitzer-Pakete über MonetizationService.HasPass um
--    (Turm: Income2x/3x, AutoCollect, OfflineVault, StaffPlus, BuildCrew · Welt: VIP, MegaGarage, Lam1 ·
--    Lifestyle: Chrono, Jetpack · Optik: TerminalDesigner, FacadeKit). Includes = Paket (HasPass zählt es mit).
-- ---------------------------------------------------------------------
Shop.GamePasses = {
	{
		Key = "VIP",
		Id = 0,
		Price = 399,
		Icon = "Λ",
		ImageId = 0,
		Name = { de = "Börsen-VIP", en = "Exchange VIP" },
		Desc = {
			de = "VIP-Balkon im Börsensaal, goldenes Λ-Namensschild + Chat-Tag, Auto-Lack „Platin“, Turm-Einkommen ×1,10.",
			en = "VIP balcony in the exchange hall, golden Λ nameplate + chat tag, “Platinum” car paint, tower income ×1.10.",
		},
	},
	{
		Key = "Income2x",
		Id = 0,
		Price = 499,
		Icon = "x2",
		ImageId = 0,
		Name = { de = "x2 Einnahmen", en = "2x Income" },
		Desc = {
			de = "Pässe-Faktor +1: dein Turm-Einkommen allein ×2. Zusammen mit x3 Einnahmen ×4 (nicht ×6).",
			en = "Pass factor +1: your tower income ×2 on its own. Together with 3x Income ×4 (not ×6).",
		},
	},
	{
		Key = "Income3x",
		Id = 0,
		Price = 1199,
		Icon = "x3",
		ImageId = 0,
		Name = { de = "x3 Einnahmen", en = "3x Income" },
		Desc = {
			de = "Pässe-Faktor +2: dein Turm-Einkommen allein ×3. Zusammen mit x2 Einnahmen ×4 – nicht ×6.",
			en = "Pass factor +2: your tower income ×3 on its own. Together with 2x Income ×4 – not ×6.",
		},
	},
	{
		Key = "AutoCollect",
		Id = 0,
		Price = 249,
		Icon = "⟳",
		ImageId = 0,
		Name = { de = "Auto-Kassierer", en = "Auto Collect" },
		Desc = {
			de = "Dein Tresor wird alle 3 s automatisch eingesammelt – egal, wo du in der Stadt bist.",
			en = "Your vault is collected automatically every 3 s – wherever you are in the city.",
		},
	},
	{
		Key = "OfflineVault",
		Id = 0,
		Price = 349,
		Icon = "☾",
		ImageId = 0,
		Name = { de = "Offline-Tresor 24 h", en = "Offline Vault 24 h" },
		Desc = {
			de = "Offline-Deckel mindestens 24 h und Offline-Rate +15 Prozentpunkte.",
			en = "Offline cap at least 24 h and offline rate +15 percentage points.",
		},
	},
	{
		Key = "StaffPlus",
		Id = 0,
		Price = 299,
		Icon = "+3",
		ImageId = 0,
		Name = { de = "Personal+", en = "Staff+" },
		Desc = {
			de = "3. Personal-Platz je Etage – nur Turm-Personal, nie Strategie-Bots.",
			en = "3rd staff slot per floor – tower staff only, never strategy bots.",
		},
	},
	{
		Key = "BuildCrew",
		Id = 0,
		Price = 399,
		Icon = "▲",
		ImageId = 0,
		Name = { de = "Bau-Crew Pro", en = "Build Crew Pro" },
		Desc = {
			de = "Bauzeiten −50 % (nie unter der Mindest-Bauzeit). Lizenz-Tore bleiben bestehen.",
			en = "Build times −50% (never below the minimum build time). Licence gates stay in place.",
		},
	},
	{
		Key = "TerminalDesigner",
		Id = 0,
		Price = 249,
		Icon = "◐",
		ImageId = 0,
		Name = { de = "Terminal-Designer", en = "Terminal Designer" },
		Desc = {
			de = "6 Terminal-Themes (Space, Gold, Arctic, Mono, Midnight, Aurora), Kerzen-/Ticker-Skins, UI-Sound-Paket. Nur Optik – keine Alarme, Layouts oder Indikatoren.",
			en = "6 terminal themes (Space, Gold, Arctic, Mono, Midnight, Aurora), candle/ticker skins, UI sound pack. Looks only – no alerts, layouts or indicators.",
		},
	},
	{
		Key = "MegaGarage",
		Id = 0,
		Price = 199,
		Icon = "P",
		ImageId = 0,
		Name = { de = "Mega-Garage", en = "Mega Garage" },
		Desc = {
			de = "+12 Auto-Plätze in deiner Garage – Platz für die ganze Sammlung.",
			en = "+12 car slots in your garage – room for your whole collection.",
		},
	},
	{
		Key = "Jetpack",
		Id = 0,
		Price = 449,
		Icon = "⇡",
		ImageId = 0,
		Name = { de = "Neon-Jetpack", en = "Neon Jetpack" },
		Desc = {
			de = "Flieg mit Neon-Spur über die Stadt: 8 s Flugzeit, lädt in 12 s nach.",
			en = "Fly over the city with a neon trail: 8 s of flight, recharges in 12 s.",
		},
	},
	{
		Key = "Lam1",
		Id = 0,
		Price = 799,
		Icon = "Λ1",
		ImageId = 0,
		Name = { de = "ΛKYTEX Λ-1 Hypercar", en = "ΛKYTEX Λ-1 Hypercar" },
		Desc = {
			de = "Exklusives Hypercar mit Neon-Spur und eigener Form (Tempo wie die besten erspielten Hypercars). Fährt sofort aus deiner Garage.",
			en = "Exclusive hypercar with a neon trail and its own shape (top speed like the best earned hypercars). Drives right out of your garage.",
		},
	},
	{
		Key = "Chrono",
		Id = 0,
		Price = 349,
		Icon = "◷",
		ImageId = 0,
		Name = { de = "Chrono-Kollektion", en = "Chrono Collection" },
		Desc = {
			de = "5 exklusive Uhren: Chrono Nacht, Aurora, Arktis, Solar und Mitternacht – am Handgelenk für alle sichtbar.",
			en = "5 exclusive watches: Chrono Night, Aurora, Arctic, Solar and Midnight – visible on your wrist to everyone.",
		},
	},
	{
		Key = "FacadeKit",
		Id = 0,
		Price = 349,
		Icon = "▦",
		ImageId = 0,
		Name = { de = "Neon-Fassaden-Kit", en = "Neon Facade Kit" },
		Desc = {
			de = "Fassade „Gold-Luxe“, 8 animierte Lichtmuster und Kronenfarben für deinen Tower.",
			en = "“Gold Luxe” facade, 8 animated light patterns and crown colours for your tower.",
		},
	},
	{
		Key = "TycoonBundle",
		Id = 0,
		Price = 749,
		Icon = "★",
		ImageId = 0,
		Includes = { "Income2x", "AutoCollect", "OfflineVault" },
		Name = { de = "Tycoon-Paket", en = "Tycoon Bundle" },
		Desc = {
			de = "Wirkung von x2 Einnahmen + Auto-Kassierer + Offline-Tresor 24 h in einem Pass. Besitzt du schon ein Teil, empfiehlt die Karte die günstigeren Einzelkäufe.",
			en = "The effect of 2x Income + Auto Collect + Offline Vault 24 h in one pass. If you already own a part, the card recommends the cheaper single passes.",
		},
	},
}

-- ---------------------------------------------------------------------
-- 2) DEVELOPER PRODUCTS (17, wiederholbar, §B14.2) – jede Gewährung deterministisch, Zahl vor dem Kauf sichtbar.
--    Kind:     Boost · Parade · Voucher · Express · Fireworks · Starter · Season · Tiers · Gift
--    Grant:    feste Gewährung (Types.Grant, nur Turm-Seite)
--    Voucher:  { Minutes, Min } – CR = Minuten Dauer-Einkommen ohne Zeitlich, mindestens Min (Angebot 10 min gültig,
--              Gewährung max(Angebot, Neuberechnung))
--    Vouchers: weitere Bau-Gutscheine (Produkt-Schlüssel) zusätzlich zu Grant
--    Express:  Sekunden (beendet die Baustelle bei Rest ≤ Express, sonst −Express; ohne Baustelle -> Token)
--    Once:     einmal je Konto (Wiederholung -> Repeat)   PerSeason: einmal je Saison (schon da -> Repeat)
--    Random:   IMMER false (keine bezahlten Zufallsartikel)
-- ---------------------------------------------------------------------
Shop.Products = {
	{
		Key = "Boost2x30",
		Id = 0,
		Price = 49,
		Kind = "Boost",
		Icon = "x2",
		ImageId = 0,
		Name = { de = "Boost x2 · 30 min", en = "Boost x2 · 30 min" },
		Desc = {
			de = "+30 min x2 Turm-Einkommen (Spielzeit – zählt nur, solange du online bist).",
			en = "+30 min of x2 tower income (playtime – only counts while you are online).",
		},
		Grant = { BoostX2 = 1800 },
		Random = false,
	},
	{
		Key = "Boost2x120",
		Id = 0,
		Price = 149,
		Kind = "Boost",
		Icon = "x2",
		ImageId = 0,
		Name = { de = "Boost x2 · 2 h", en = "Boost x2 · 2 h" },
		Desc = {
			de = "+2 h x2 Turm-Einkommen (Spielzeit – zählt nur, solange du online bist).",
			en = "+2 h of x2 tower income (playtime – only counts while you are online).",
		},
		Grant = { BoostX2 = 7200 },
		Random = false,
	},
	{
		Key = "Boost5x10",
		Id = 0,
		Price = 99,
		Kind = "Boost",
		Icon = "x5",
		ImageId = 0,
		Name = { de = "Turbo x5 · 10 min", en = "Turbo x5 · 10 min" },
		Desc = {
			de = "+10 min x5 Turm-Einkommen (Spielzeit). Überlagert x2 – deine x2-Zeit pausiert so lange.",
			en = "+10 min of x5 tower income (playtime). Overrides x2 – your x2 time pauses meanwhile.",
		},
		Grant = { BoostX5 = 600 },
		Random = false,
	},
	{
		Key = "BullParade",
		Id = 0,
		Price = 199,
		Kind = "Parade",
		Icon = "♉",
		ImageId = 0,
		Name = { de = "Bullen-Parade (ganzer Server)", en = "Bull Parade (whole server)" },
		Desc = {
			de = "×1,5 Turm-Einkommen für alle im Server, 15 min (erneuter Kauf verlängert, höchstens 60 min im Voraus). Goldene Parade um den Ring und ein Danke-Banner mit deinem Namen.",
			en = "×1.5 tower income for everyone in the server, 15 min (another purchase extends it, at most 60 min ahead). Golden parade around the ring and a thank-you banner with your name.",
		},
		Random = false,
	},
	{
		Key = "CreditsS",
		Id = 0,
		Price = 49,
		Kind = "Voucher",
		Icon = "S",
		ImageId = 0,
		Name = { de = "Bau-Gutschein S", en = "Build Voucher S" },
		Desc = {
			de = "CR = 30 min deines Dauer-Einkommens (ohne Boosts), mindestens 5.000 CR. Nur CR.",
			en = "CR = 30 min of your steady income (without boosts), at least 5,000 CR. CR only.",
		},
		Voucher = { Minutes = 30, Min = 5000 },
		Random = false,
	},
	{
		Key = "CreditsM",
		Id = 0,
		Price = 149,
		Kind = "Voucher",
		Icon = "M",
		ImageId = 0,
		Name = { de = "Bau-Gutschein M", en = "Build Voucher M" },
		Desc = {
			de = "CR = 2 h deines Dauer-Einkommens (ohne Boosts), mindestens 20.000 CR. Nur CR.",
			en = "CR = 2 h of your steady income (without boosts), at least 20,000 CR. CR only.",
		},
		Voucher = { Minutes = 120, Min = 20000 },
		Random = false,
	},
	{
		Key = "CreditsL",
		Id = 0,
		Price = 399,
		Kind = "Voucher",
		Icon = "L",
		ImageId = 0,
		Name = { de = "Bau-Gutschein L", en = "Build Voucher L" },
		Desc = {
			de = "CR = 6 h deines Dauer-Einkommens (ohne Boosts), mindestens 60.000 CR. Nur CR.",
			en = "CR = 6 h of your steady income (without boosts), at least 60,000 CR. CR only.",
		},
		Voucher = { Minutes = 360, Min = 60000 },
		Random = false,
	},
	{
		Key = "CreditsXL",
		Id = 0,
		Price = 899,
		Kind = "Voucher",
		Icon = "XL",
		ImageId = 0,
		Name = { de = "Bau-Gutschein XL", en = "Build Voucher XL" },
		Desc = {
			de = "CR = 16 h deines Dauer-Einkommens (ohne Boosts), mindestens 150.000 CR. Nur CR.",
			en = "CR = 16 h of your steady income (without boosts), at least 150,000 CR. CR only.",
		},
		Voucher = { Minutes = 960, Min = 150000 },
		Random = false,
	},
	{
		Key = "ExpressS",
		Id = 0,
		Price = 19,
		Kind = "Express",
		Icon = "»",
		ImageId = 0,
		Name = { de = "Bau-Express S", en = "Build Express S" },
		Desc = {
			de = "Beendet deine Baustelle bei ≤ 10 min Restzeit, sonst −10 min. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).",
			en = "Finishes your build with ≤ 10 min left, otherwise −10 min. No build running: token for the next build (never expires).",
		},
		Express = 600,
		Random = false,
	},
	{
		Key = "ExpressM",
		Id = 0,
		Price = 39,
		Kind = "Express",
		Icon = "»",
		ImageId = 0,
		Name = { de = "Bau-Express M", en = "Build Express M" },
		Desc = {
			de = "Beendet deine Baustelle bei ≤ 60 min Restzeit, sonst −60 min. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).",
			en = "Finishes your build with ≤ 60 min left, otherwise −60 min. No build running: token for the next build (never expires).",
		},
		Express = 3600,
		Random = false,
	},
	{
		Key = "ExpressL",
		Id = 0,
		Price = 79,
		Kind = "Express",
		Icon = "»",
		ImageId = 0,
		Name = { de = "Bau-Express L", en = "Build Express L" },
		Desc = {
			de = "Beendet deine Baustelle bei ≤ 3 h Restzeit, sonst −3 h. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).",
			en = "Finishes your build with ≤ 3 h left, otherwise −3 h. No build running: token for the next build (never expires).",
		},
		Express = 10800,
		Random = false,
	},
	{
		Key = "Fireworks",
		Id = 0,
		Price = 29,
		Kind = "Fireworks",
		Icon = "✶",
		ImageId = 0,
		Name = { de = "Feuerwerk über deinem Tower", en = "Fireworks over your tower" },
		Desc = {
			de = "20-s-Show über deinem Tower, für alle im Server sichtbar.",
			en = "20-second show above your tower, visible to everyone in the server.",
		},
		Random = false,
	},
	{
		Key = "Starter",
		Id = 0,
		Price = 99,
		Kind = "Starter",
		Icon = "✦",
		ImageId = 0,
		Name = { de = "Starter-Paket", en = "Starter Pack" },
		Desc = {
			de = "Auto „Λ Kompakt Neon“, Uhr „Erste Glocke“, Boost x2 · 2 h, Bau-Gutschein M, Fassaden-Neon „Startup“, Namensrahmen „Gründer“. Einmal je Konto – ein zweiter Kauf gibt 2 × Bau-Gutschein M.",
			en = "“Λ Compact Neon” car, “First Bell” watch, Boost x2 · 2 h, Build Voucher M, “Startup” facade neon, “Founder” name frame. Once per account – a second purchase gives 2 × Build Voucher M.",
		},
		Grant = {
			Cars = { "LamNeon" },
			Watches = { "FirstBell" },
			BoostX2 = 7200,
			Cosmetics = { "Startup", "FounderFrame" },
		},
		Vouchers = { "CreditsM" },
		Once = true,
		Repeat = { Vouchers = { "CreditsM", "CreditsM" } },
		Random = false,
	},
	{
		Key = "SeasonPremium",
		Id = 0,
		Price = 399,
		Kind = "Season",
		Icon = "◆",
		ImageId = 0,
		Name = { de = "Skyline-Pass Premium (Saison)", en = "Skyline Pass Premium (season)" },
		Desc = {
			de = "Schaltet die Premium-Spur dieser Saison frei – rückwirkend für alle erreichten Stufen. Nur Turm-Belohnungen (CR, Deko, Kosmetik, Boosts, Auto).",
			en = "Unlocks this season's premium track – retroactively for every tier you reached. Tower rewards only (CR, decor, cosmetics, boosts, car).",
		},
		Grant = { SeasonPremium = true },
		PerSeason = true,
		Repeat = { Vouchers = { "CreditsL" } },
		Random = false,
	},
	{
		Key = "SeasonTier1",
		Id = 0,
		Price = 39,
		Kind = "Tiers",
		Icon = "+1",
		ImageId = 0,
		Name = { de = "+1 Pass-Stufe", en = "+1 Pass Tier" },
		Desc = {
			de = "Eine Skyline-Pass-Stufe. Gekaufte Stufen schalten nur Kosmetik frei – CR, Boosts und Token gibt es nur mit verdienter Saison-XP.",
			en = "One Skyline Pass tier. Bought tiers only unlock cosmetics – CR, boosts and tokens require earned season XP.",
		},
		Grant = { SeasonTiers = 1 },
		Random = false,
	},
	{
		Key = "SeasonTier10",
		Id = 0,
		Price = 299,
		Kind = "Tiers",
		Icon = "+10",
		ImageId = 0,
		Name = { de = "+10 Pass-Stufen", en = "+10 Pass Tiers" },
		Desc = {
			de = "Zehn Skyline-Pass-Stufen. Gekaufte Stufen schalten nur Kosmetik frei – CR, Boosts und Token gibt es nur mit verdienter Saison-XP.",
			en = "Ten Skyline Pass tiers. Bought tiers only unlock cosmetics – CR, boosts and tokens require earned season XP.",
		},
		Grant = { SeasonTiers = 10 },
		Random = false,
	},
	{
		Key = "GiftBoost",
		Id = 0,
		Price = 59,
		Kind = "Gift",
		Icon = "♥",
		ImageId = 0,
		Name = { de = "Geschenk-Boost", en = "Gift Boost" },
		Desc = {
			de = "Boost x2 · 30 min für einen Spieler deiner Wahl in diesem Server. Ist er beim Abschluss nicht mehr da, bekommst du den Boost selbst. Nur, wo Geschenke erlaubt sind.",
			en = "Boost x2 · 30 min for a player of your choice in this server. If they have left when the purchase completes, you get the boost yourself. Only where gifts are allowed.",
		},
		Grant = { BoostX2 = 1800 },
		Gift = true,
		Random = false,
	},
}

-- ---------------------------------------------------------------------
-- 3) ABO „Vorstands-Club“ (Experience Subscription, §B14.3) – Id = "" heißt "noch nicht eingerichtet".
--    Preis im Creator Dashboard: 4,99 $ Landeswährung (ID-verifiziert) bzw. 449 R$/Monat. Nie "PRO".
-- ---------------------------------------------------------------------
Shop.Subscription = {
	Key = "Club",
	Id = "", -- z. B. "EXP-1234567890123456789"
	Price = 449, -- R$/Monat (Planwert; Anzeige kommt live vom Marktplatz)
	Icon = "♛",
	ImageId = 0,
	DailyVoucher = "CreditsS", -- tägliche Abholung (ShopClubClaim, 1× je UTC-Tag)
	Name = { de = "Vorstands-Club", en = "Executive Club" },
	Desc = {
		de = "Täglich ein Bau-Gutschein S zum Abholen, Turm-Einkommen ×1,15, +4 h Offline-Deckel, exklusiver Auto-Lack „Club Noir“, Dachterrasse im Börsensaal, +1 Serien-Schutz je Woche, Tag „Club“.",
		en = "A Build Voucher S to claim every day, tower income ×1.15, +4 h offline cap, exclusive “Club Noir” car paint, rooftop terrace in the exchange hall, +1 streak shield per week, “Club” tag.",
	},
}

-- ---------------------------------------------------------------------
-- 4) FIREWALL & POLICY (§B14.5, §C11.4)
-- ---------------------------------------------------------------------
Shop.ForbiddenRobuxFields = {
	"Depot",
	"AKY",
	"Basis",
	"Xp",
	"TraderXp",
	"Licence",
	"KnowHow",
	"Ruf",
	"Stars",
	"BotSlots",
	"BotLevel",
	"Alerts",
	"Watchlists",
	"Layouts",
	"MultiChart",
	"Research",
	"MarketInfo",
	"ExamPass",
}
Shop.RandomItemsEnabled = false -- keine bezahlten Zufallsartikel (Muss-Regel 6, SelfTest "NoPaidRandom")

-- Felder einer Gewährung (Types.Grant) und ihre Form: number = ganze Zahl ≥ 0 · list = Liste von Schlüsseln ·
-- map = { [Schlüssel] = Anzahl ≥ 1 } · boolean. ExpressTokens = Sekunden EINES Bau-Express (laufende Baustelle,
-- sonst Token). Alles andere lehnt ShopService.Core.ValidateGrant ab.
Shop.GrantFields = {
	Credits = "number",
	Cars = "list",
	Watches = "list",
	Accessories = "list",
	Decor = "map",
	Cosmetics = "list",
	Titles = "list",
	BoostX2 = "number",
	BoostX5 = "number",
	ExpressTokens = "number",
	InstantTokens = "number",
	SeasonPremium = "boolean",
	SeasonTiers = "number",
	SeasonXp = "number",
}
Shop.GrantListMax = 64 -- höchstens so viele Einträge je Liste in einer Gewährung
Shop.GrantNumberMax =
	{ BoostX2 = 2592000, BoostX5 = 2592000, ExpressTokens = 86400, InstantTokens = 99, SeasonTiers = 50 }

-- ---------------------------------------------------------------------
-- 5) CR-KONTO (§C5.9) – ShopService.Credit/Debit sind der EINZIGE Weg; Quellen/Senken-Whitelist
-- ---------------------------------------------------------------------
Shop.Sources = {
	"Income",
	"Vault",
	"Offline",
	"Transfer",
	"Quest",
	"Login",
	"Event",
	"Pickup",
	"Rain",
	"Code",
	"Purchase",
	"Admin",
	"Achievement",
	"Season",
	"Tutorial",
	"Refund",
	"League", -- Liga-Belohnung (RewardService)
	"WinBack", -- Rückkehr-Geschenk (RewardService)
	"Referral", -- Freunde-Einladung (CommunityService)
}
Shop.Sinks = {
	"Floor",
	"RoomLevel",
	"Room",
	"Staff",
	"Efficiency",
	"Decor",
	"Car",
	"Tune",
	"Watch",
	"Accessory",
	"Admin",
	"Ipo", -- Börsengang: CR starten neu (TowerService.ResetForIpo)
}
Shop.MetricsFlushSeconds = 60 -- Quellen/Senken je Spieler gebündelt an MetricsService (Roblox-Budget)

-- ---------------------------------------------------------------------
-- 6) ANGEBOTE (§B14.4, Muss-Regel 17) – max. 1 Popup je Sitzung, nie in Sitzung 1, nur nach ≥ 15 min und direkt
--    nach einem positiven Moment (Stufen-Morph); nie bei Crash/Rally-Warnung, Tutorial, Willkommen-Bericht,
--    Admin-Abuse; der Client wartet zusätzlich, solange Terminal/Order-Ticket offen sind.
-- ---------------------------------------------------------------------
Shop.QuoteSeconds = 600 -- Bau-Gutschein-Angebot 10 min gültig (fester Ablauf, kein Neustart)
Shop.MaxOffersPerSession = 1
Shop.OfferMinMinutes = 15 -- frühestens nach so vielen Minuten in der Sitzung
Shop.OfferMinSession = 2 -- frühestens ab der 2. Sitzung (nie in der ersten)
Shop.OfferDelaySeconds = 4 -- nach dem Stufen-Morph kurz warten (die Animation gehört dem Spieler)
Shop.OfferMarketBlockSeconds = 900 -- nach Warnung/Crash/Rally-Meldung so lange kein Angebot
Shop.OfferOrder = { "Starter", "TycoonBundle", "SeasonPremium" } -- automatisches Angebot: erstes passendes
Shop.OfferClientWait = 120 -- Client wartet höchstens so lange auf einen ruhigen Moment, sonst entfällt das Popup

-- ---------------------------------------------------------------------
-- 7) BOUTIQUE-ROTATION (ShopService.Rotation, deterministisch, auf allen Servern gleich)
-- ---------------------------------------------------------------------
Shop.BoutiqueHours = 4
Shop.BoutiqueSlots = 6

-- ---------------------------------------------------------------------
-- 8) SERVER-WEITE PRODUKTE, GESCHENK, NOTSCHALTER
-- ---------------------------------------------------------------------
Shop.Parade = { Seconds = 900, CapSeconds = 3600 } -- 15 min je Kauf, höchstens 60 min im Voraus (§B10.3)
Shop.Fireworks = { Seconds = 20 }
Shop.GiftHoldSeconds = 180 -- so lange gilt der im Shop gewählte Empfänger (ShopPrecheck -> Roblox-Kauf)
Shop.PolicyWaitSeconds = 5 -- ShopPrecheck wartet höchstens so lange auf die PolicyService-Antwort
Shop.Fixed = { Vip = 1.10, Club = 1.15, Premium = 1.10 } -- Rückfall, falls Config.Tower.Mult fehlt
-- Notschalter (live über Config.LiveFields "Shop.Disabled.<Key>"): true = Kauf im Shop gesperrt.
-- Bereits bezahlte Käufe werden IMMER gutgeschrieben (nie einen Beleg verschlucken).
-- TerminalDesigner ist gesperrt, bis die 6 Terminal-Themes im Terminal (WP5) wirklich wählbar sind – nie einen Pass
-- ohne Wirkung verkaufen (Muss-Regel 17 / §0.8 Punkt 4: exakte Wirkung vor dem Kauf). Danach hier entfernen.
Shop.Disabled = { TerminalDesigner = true } :: { [string]: boolean }

-- =====================================================================
-- 9) NACHSCHLAGEN (doppelte Keys/Ids = Fehler beim Laden)
-- =====================================================================
Shop.ProductsByKey = {} :: { [string]: any }
Shop.ProductsById = {} :: { [number]: any }
Shop.PassesByKey = {} :: { [string]: any }
Shop.PassesById = {} :: { [number]: any }

for _, product in ipairs(Shop.Products) do
	assert(Shop.ProductsByKey[product.Key] == nil, "[Config.Shop] Doppelter Produkt-Key: " .. product.Key)
	Shop.ProductsByKey[product.Key] = product
	if product.Id ~= 0 then
		assert(Shop.ProductsById[product.Id] == nil, "[Config.Shop] Doppelte Produkt-Id: " .. tostring(product.Id))
		Shop.ProductsById[product.Id] = product
	end
end
for _, pass in ipairs(Shop.GamePasses) do
	assert(Shop.PassesByKey[pass.Key] == nil, "[Config.Shop] Doppelter Pass-Key: " .. pass.Key)
	assert(Shop.ProductsByKey[pass.Key] == nil, "[Config.Shop] Pass-Key auch als Produkt: " .. pass.Key)
	Shop.PassesByKey[pass.Key] = pass
	if pass.Id ~= 0 then
		assert(Shop.PassesById[pass.Id] == nil, "[Config.Shop] Doppelte Pass-Id: " .. tostring(pass.Id))
		Shop.PassesById[pass.Id] = pass
	end
end

local forbiddenSet: { [string]: boolean } = {}
for _, field in ipairs(Shop.ForbiddenRobuxFields) do
	forbiddenSet[field] = true
end

function Shop.IsKnown(key: string): boolean
	return type(key) == "string"
		and (Shop.PassesByKey[key] ~= nil or Shop.ProductsByKey[key] ~= nil or key == Shop.Subscription.Key)
end

-- =====================================================================
-- 10) HELFER (rein, ohne Roblox-Dienste)
-- =====================================================================
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isInt(n: any): boolean
	return finite(n) and n % 1 == 0
end

-- Summe der Planpreise der enthaltenen Pässe (0 = kein Paket)
function Shop.BundleValue(passKey: string): number
	local pass = Shop.PassesByKey[passKey]
	if type(pass) ~= "table" or type(pass.Includes) ~= "table" then
		return 0
	end
	local sum = 0
	for _, key in ipairs(pass.Includes) do
		local part = Shop.PassesByKey[key]
		if part and isInt(part.Price) then
			sum += part.Price
		end
	end
	return sum
end

-- Echter Rabatt in ganzen Prozent. value/price = Live-Preise (Einzelsumme, Paketpreis); ohne -> Planpreise.
function Shop.BundleDiscountPct(passKey: string, value: number?, price: number?): number
	local pass = Shop.PassesByKey[passKey]
	local single = if finite(value) then value :: number else Shop.BundleValue(passKey)
	local bundle = if finite(price) then price :: number else (if pass then tonumber(pass.Price) else nil)
	if not finite(single) or not finite(bundle) or single <= 0 or (bundle :: number) >= single then
		return 0
	end
	return math.floor((1 - (bundle :: number) / single) * 100 + 0.5)
end

-- CR eines Bau-Gutscheins: Minuten × Dauer-Einkommen/s (ohne Zeitlich), mindestens Min, ganzzahlig, ≤ 9e15
function Shop.VoucherCredits(product: any, steadyPerSec: number): number
	local voucher = type(product) == "table" and product.Voucher or nil
	if type(voucher) ~= "table" or not finite(voucher.Minutes) or not finite(voucher.Min) then
		return 0
	end
	local rate = if finite(steadyPerSec) and steadyPerSec > 0 then steadyPerSec else 0
	local value = math.floor(rate * voucher.Minutes * 60)
	return math.clamp(math.max(math.floor(voucher.Min), value), 0, MAX_MONEY)
end

-- Kopie einer Gewährung. robux = true: Felder aus ForbiddenRobuxFields fallen weg (zweite Rückgabe = gestrichene).
-- Nicht-String-Schlüssel fallen immer weg. Tabellen werden eine Ebene tief kopiert (Listen/Deko-Mengen).
function Shop.SanitizeGrant(grant: any, robux: boolean): ({ [string]: any }, { string })
	local clean: { [string]: any } = {}
	local removed: { string } = {}
	if type(grant) ~= "table" then
		return clean, removed
	end
	for field, value in pairs(grant) do
		if type(field) ~= "string" then
			continue
		end
		if robux and forbiddenSet[field] then
			table.insert(removed, field)
		elseif type(value) == "table" then
			local copy: { [any]: any } = {}
			for k, v in pairs(value) do
				if type(v) ~= "table" then
					copy[k] = v
				end
			end
			clean[field] = copy
		else
			clean[field] = value
		end
	end
	table.sort(removed)
	return clean, removed
end

-- Gregorianischer Tag -> Tage seit 1970 (für ParseUtc)
local function daysFromCivil(year: number, month: number, day: number): number
	local y = year - (if month <= 2 then 1 else 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- "2026-10-12T00:00:00Z" -> Sekunden seit 1970 (UTC); kaputt -> nil
function Shop.ParseUtc(text: string): number?
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
	if not y then
		return nil
	end
	local year, month, day = tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number
	local hour, minute, second = tonumber(h) :: number, tonumber(mi) :: number, tonumber(s) :: number
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 59 then
		return nil
	end
	return daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
end

-- Aktive Saison-Id (Config.Season): innerhalb [StartUtc, EndUtc) -> deren Id; vor allen -> erste;
-- nach der letzten -> Rolling (gleiche Länge, fortlaufende Id) oder letzte.
function Shop.SeasonIdAt(season: any, now: number): number
	local list = type(season) == "table" and season.Seasons or nil
	if type(list) ~= "table" or #list == 0 then
		return 1
	end
	local first = list[1]
	local firstStart = Shop.ParseUtc(first.StartUtc)
	if firstStart and now < firstStart then
		return if isInt(first.Id) then first.Id else 1
	end
	-- last = zuletzt begonnene Saison (Lücke zwischen zwei Saisons -> die vorige gilt weiter, genau wie
	-- RewardService: Rolling erst nach der LETZTEN festen Saison)
	local last = first
	local lastIndex = 1
	for index, entry in ipairs(list) do
		if type(entry) == "table" and isInt(entry.Id) then
			local startAt, endAt = Shop.ParseUtc(entry.StartUtc), Shop.ParseUtc(entry.EndUtc)
			if startAt and endAt and now >= startAt and now < endAt then
				return entry.Id
			end
			if startAt and now >= startAt then
				last = entry
				lastIndex = index
			end
		end
	end
	local lastId = if isInt(last.Id) then last.Id else 1
	if lastIndex < #list then
		return lastId
	end
	local rolling = season.Rolling
	local lastEnd = Shop.ParseUtc(last.EndUtc)
	if type(rolling) == "table" and rolling.Enabled == true and lastEnd and now >= lastEnd then
		local length = (if finite(rolling.LengthDays) and rolling.LengthDays >= 1 then rolling.LengthDays else 28)
			* 86400
		local maxSeasons = if isInt(season.MaxSeasons) then season.MaxSeasons else 999
		local extra = math.floor((now - lastEnd) / length) + 1
		return math.min(lastId + extra, math.max(lastId, maxSeasons))
	end
	return lastId
end

-- =====================================================================
-- 11) PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local KINDS: { [string]: boolean } = {
	Boost = true,
	Parade = true,
	Voucher = true,
	Express = true,
	Fireworks = true,
	Starter = true,
	Season = true,
	Tiers = true,
	Gift = true,
}
local PRODUCT_FIELDS: { [string]: boolean } = {
	Key = true,
	Id = true,
	Price = true,
	Kind = true,
	Icon = true,
	ImageId = true,
	Name = true,
	Desc = true,
	Grant = true,
	Voucher = true,
	Vouchers = true,
	Express = true,
	Once = true,
	PerSeason = true,
	Repeat = true,
	Gift = true,
	Random = true,
}
local PASS_FIELDS: { [string]: boolean } =
	{ Key = true, Id = true, Price = true, Icon = true, ImageId = true, Name = true, Desc = true, Includes = true }
-- Zufalls-Felder, die es im Shop nie geben darf (NoPaidRandom)
local RANDOM_FIELDS: { [string]: boolean } = { Odds = true, Weights = true, Weight = true, Chance = true, Pity = true }

local function checkPair(add: (string) -> (), where: string, pair: any, maxLen: number)
	if type(pair) ~= "table" then
		add(where .. ": { de, en } erwartet")
		return
	end
	for _, lang in ipairs({ "de", "en" }) do
		local text = pair[lang]
		if type(text) ~= "string" or text == "" or #text > maxLen then
			add(("%s.%s: Text (1–%d Zeichen) erwartet"):format(where, lang, maxLen))
		end
	end
end

local function checkGrant(add: (string) -> (), where: string, grant: any, config: any)
	if type(grant) ~= "table" then
		add(where .. ": Tabelle erwartet")
		return
	end
	for field, value in pairs(grant) do
		local kind = Shop.GrantFields[field]
		if forbiddenSet[field] then
			add(("%s.%s: verbotenes Robux-Feld (Firewall §0.4)"):format(where, tostring(field)))
		elseif kind == nil then
			add(("%s.%s: unbekanntes Grant-Feld"):format(where, tostring(field)))
		elseif kind == "number" then
			if not isInt(value) or value < 1 then
				add(("%s.%s: ganze Zahl ≥ 1 erwartet"):format(where, field))
			end
		elseif kind == "boolean" then
			if value ~= true then
				add(("%s.%s: true erwartet"):format(where, field))
			end
		elseif kind == "list" then
			if type(value) ~= "table" or #value == 0 then
				add(("%s.%s: Liste von Schlüsseln erwartet"):format(where, field))
			end
		elseif kind == "map" and type(value) ~= "table" then
			add(("%s.%s: { [Schlüssel] = Anzahl } erwartet"):format(where, field))
		end
	end
	-- Querverweise (nur wenn die Besitzer-Configs geladen sind)
	local vehicles = config and config.Vehicles
	if type(grant.Cars) == "table" and type(vehicles) == "table" and type(vehicles.Car) == "function" then
		for _, key in ipairs(grant.Cars) do
			local ok, car = pcall(vehicles.Car, key)
			if not ok or car == nil then
				add(("%s.Cars: Auto %s fehlt in Config.Vehicles"):format(where, tostring(key)))
			end
		end
	end
	local lifestyle = config and config.Lifestyle
	if type(lifestyle) == "table" and type(lifestyle.KindOf) == "table" then
		for _, key in ipairs(if type(grant.Watches) == "table" then grant.Watches else {}) do
			if lifestyle.KindOf[key] ~= "Watch" then
				add(("%s.Watches: Uhr %s fehlt in Config.Lifestyle"):format(where, tostring(key)))
			end
		end
		for _, key in ipairs(if type(grant.Accessories) == "table" then grant.Accessories else {}) do
			if lifestyle.KindOf[key] ~= "Accessory" then
				add(("%s.Accessories: Accessoire %s fehlt in Config.Lifestyle"):format(where, tostring(key)))
			end
		end
	end
end

function Shop.Validate(config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Shop." .. text)
	end

	-- Pässe
	if #Shop.GamePasses ~= 14 then
		add(("GamePasses: 14 Pässe erwartet (§B14.1), gefunden %d"):format(#Shop.GamePasses))
	end
	for i, pass in ipairs(Shop.GamePasses) do
		local where = ("GamePasses[%d] %s"):format(i, tostring(pass.Key))
		if type(pass.Key) ~= "string" or not string.match(pass.Key, "^%a[%w]*$") then
			add(where .. ".Key: Buchstaben/Ziffern erwartet")
		end
		if not isInt(pass.Id) or pass.Id < 0 then
			add(where .. ".Id: ganze Zahl ≥ 0 erwartet (0 = Bald verfügbar)")
		end
		if not isInt(pass.Price) or pass.Price < 1 then
			add(where .. ".Price: ganze Zahl ≥ 1 erwartet")
		end
		checkPair(add, where .. ".Name", pass.Name, 50)
		checkPair(add, where .. ".Desc", pass.Desc, 400)
		for field in pairs(pass) do
			if RANDOM_FIELDS[field] or field == "Random" then
				add(("%s.%s: Zufalls-Feld verboten (NoPaidRandom)"):format(where, tostring(field)))
			elseif not PASS_FIELDS[field] then
				add(("%s.%s: unbekanntes Feld"):format(where, tostring(field)))
			end
		end
		if pass.Includes ~= nil then
			if type(pass.Includes) ~= "table" or #pass.Includes < 2 then
				add(where .. ".Includes: Liste von mind. 2 Pass-Schlüsseln erwartet")
			else
				for _, key in ipairs(pass.Includes) do
					local part = Shop.PassesByKey[key]
					if part == nil or part.Includes ~= nil then
						add(("%s.Includes: %s ist kein einfacher Pass"):format(where, tostring(key)))
					end
				end
				local value = Shop.BundleValue(pass.Key)
				if value <= pass.Price then
					add(where .. ": Paket muss echt günstiger sein als die Einzelpässe (keine Fake-Rabatte)")
				end
			end
		end
	end

	-- Produkte
	if #Shop.Products ~= 17 then
		add(("Products: 17 Produkte erwartet (§B14.2), gefunden %d"):format(#Shop.Products))
	end
	for i, product in ipairs(Shop.Products) do
		local where = ("Products[%d] %s"):format(i, tostring(product.Key))
		if type(product.Key) ~= "string" or not string.match(product.Key, "^%a[%w]*$") then
			add(where .. ".Key: Buchstaben/Ziffern erwartet")
		end
		if not isInt(product.Id) or product.Id < 0 then
			add(where .. ".Id: ganze Zahl ≥ 0 erwartet (0 = Bald verfügbar)")
		end
		if not isInt(product.Price) or product.Price < 1 then
			add(where .. ".Price: ganze Zahl ≥ 1 erwartet")
		end
		if not KINDS[product.Kind] then
			add(where .. ".Kind: unbekannte Art")
		end
		if product.Random ~= false then
			add(where .. ".Random: muss false sein (keine bezahlten Zufallsartikel)")
		end
		checkPair(add, where .. ".Name", product.Name, 50)
		checkPair(add, where .. ".Desc", product.Desc, 400)
		for field in pairs(product) do
			if RANDOM_FIELDS[field] then
				add(("%s.%s: Zufalls-Feld verboten (NoPaidRandom)"):format(where, tostring(field)))
			elseif not PRODUCT_FIELDS[field] then
				add(("%s.%s: unbekanntes Feld"):format(where, tostring(field)))
			end
		end
		if product.Grant ~= nil then
			checkGrant(add, where .. ".Grant", product.Grant, config)
		end
		if product.Kind == "Voucher" then
			local voucher = product.Voucher
			if type(voucher) ~= "table" or not finite(voucher.Minutes) or voucher.Minutes <= 0 then
				add(where .. ".Voucher.Minutes: Zahl > 0 erwartet")
			end
			if type(voucher) ~= "table" or not isInt(voucher.Min) or voucher.Min < 1 or voucher.Min >= 1e14 then
				add(where .. ".Voucher.Min: ganze Zahl 1 … 1e14 erwartet")
			end
		end
		if product.Kind == "Express" and (not isInt(product.Express) or product.Express < 60) then
			add(where .. ".Express: Sekunden (ganze Zahl ≥ 60) erwartet")
		end
		local voucherLists: { [string]: any } = { Vouchers = product.Vouchers }
		if type(product.Repeat) == "table" then
			voucherLists["Repeat.Vouchers"] = product.Repeat.Vouchers
		end
		for label, list in pairs(voucherLists) do
			if type(list) ~= "table" then
				add(("%s.%s: Liste erwartet"):format(where, label))
			else
				for _, key in ipairs(list) do
					local voucher = Shop.ProductsByKey[key]
					if voucher == nil or voucher.Kind ~= "Voucher" then
						add(("%s.%s: %s ist kein Bau-Gutschein"):format(where, label, tostring(key)))
					end
				end
			end
		end
		if (product.Once == true or product.PerSeason == true) and type(product.Repeat) ~= "table" then
			add(where .. ".Repeat: Ersatz für den Wiederholungskauf erwartet")
		end
		if product.Repeat ~= nil and type(product.Repeat) == "table" then
			if product.Repeat.Grant ~= nil then
				checkGrant(add, where .. ".Repeat.Grant", product.Repeat.Grant, config)
			end
		end
	end

	-- Abo
	local sub = Shop.Subscription
	if type(sub) ~= "table" or type(sub.Id) ~= "string" then
		add('Subscription.Id: Text erwartet ("" = Bald verfügbar)')
	else
		if not isInt(sub.Price) or sub.Price < 49 then
			add("Subscription.Price: mindestens 49 R$ (subscriptions.md)")
		end
		checkPair(add, "Subscription.Name", sub.Name, 50)
		checkPair(add, "Subscription.Desc", sub.Desc, 400)
		local daily = Shop.ProductsByKey[sub.DailyVoucher]
		if daily == nil or daily.Kind ~= "Voucher" then
			add("Subscription.DailyVoucher: Bau-Gutschein-Schlüssel erwartet")
		end
		if Shop.PassesByKey[sub.Key] or Shop.ProductsByKey[sub.Key] then
			add("Subscription.Key: darf kein Pass-/Produkt-Schlüssel sein")
		end
	end

	-- Firewall & Zufall
	if Shop.RandomItemsEnabled ~= false then
		add("RandomItemsEnabled: muss false sein (Muss-Regel 6)")
	end
	for _, needed in ipairs({ "Depot", "AKY", "Basis", "Xp", "Licence", "KnowHow", "Ruf", "Stars" }) do
		if not forbiddenSet[needed] then
			add("ForbiddenRobuxFields: " .. needed .. " fehlt (§B14.5)")
		end
	end
	for field in pairs(Shop.GrantFields) do
		if forbiddenSet[field] then
			add("GrantFields." .. field .. ": verbotenes Feld darf kein Grant-Feld sein")
		end
	end

	-- Zahlen
	local function positive(name: string, value: any, integer: boolean)
		if not finite(value) or value <= 0 or (integer and value % 1 ~= 0) then
			add(name .. (if integer then ": ganze Zahl > 0 erwartet" else ": Zahl > 0 erwartet"))
		end
	end
	positive("QuoteSeconds", Shop.QuoteSeconds, true)
	positive("OfferMinMinutes", Shop.OfferMinMinutes, false)
	positive("OfferMinSession", Shop.OfferMinSession, true)
	positive("OfferMarketBlockSeconds", Shop.OfferMarketBlockSeconds, true)
	positive("OfferClientWait", Shop.OfferClientWait, true)
	positive("BoutiqueHours", Shop.BoutiqueHours, false)
	positive("BoutiqueSlots", Shop.BoutiqueSlots, true)
	positive("GiftHoldSeconds", Shop.GiftHoldSeconds, true)
	positive("PolicyWaitSeconds", Shop.PolicyWaitSeconds, false)
	positive("MetricsFlushSeconds", Shop.MetricsFlushSeconds, true)
	positive("Parade.Seconds", Shop.Parade.Seconds, true)
	positive("Fireworks.Seconds", Shop.Fireworks.Seconds, true)
	if not isInt(Shop.MaxOffersPerSession) or Shop.MaxOffersPerSession < 0 or Shop.MaxOffersPerSession > 1 then
		add("MaxOffersPerSession: 0 oder 1 (Muss-Regel 17)")
	end
	if Shop.OfferMinSession < 2 then
		add("OfferMinSession: mindestens 2 (nie in der ersten Sitzung)")
	end
	if not finite(Shop.Parade.CapSeconds) or Shop.Parade.CapSeconds < Shop.Parade.Seconds then
		add("Parade.CapSeconds: mindestens Parade.Seconds")
	end
	if not finite(Shop.OfferDelaySeconds) or Shop.OfferDelaySeconds < 0 then
		add("OfferDelaySeconds: Zahl ≥ 0 erwartet")
	end
	for _, key in ipairs(Shop.OfferOrder) do
		if not Shop.IsKnown(key) then
			add("OfferOrder: unbekannter Schlüssel " .. tostring(key))
		end
	end
	for key in pairs(Shop.Fixed) do
		if not finite(Shop.Fixed[key]) or Shop.Fixed[key] < 1 then
			add("Fixed." .. key .. ": Faktor ≥ 1 erwartet")
		end
	end
	for key, value in pairs(Shop.Disabled) do
		if type(value) ~= "boolean" or not Shop.IsKnown(key) then
			add("Disabled." .. tostring(key) .. ": bekannter Schlüssel = true/false erwartet")
		end
	end
	local seen: { [string]: boolean } = {}
	for _, list in ipairs({ Shop.Sources, Shop.Sinks }) do
		table.clear(seen)
		for _, name in ipairs(list) do
			if type(name) ~= "string" or seen[name] then
				add("Sources/Sinks: doppelter oder ungültiger Eintrag " .. tostring(name))
			end
			seen[name] = true
		end
	end
	return errors
end

return Shop
