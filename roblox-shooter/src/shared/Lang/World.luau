--!strict
-- =====================================================================
--  CLUTCH CLASH – Texte "world." (Shared/Lang/World)
--  Besitzer: WP2 (Welt: Lobby, Arenen, Maps, Licht). Nur Schlüssel mit Präfix "world.".
--  Platzhalter wie string.format: %s = Text, %d = ganze Zahl.
--
--  Benutzt von:
--    LobbyBuilder  – Schilder in der Welt sind für ALLE gleich, darum zweisprachig
--                    („DUELLE / DUELS“): Text = de .. " / " .. en (gleich -> nur einmal)
--    ArenaLook / Vote-UI (WP5) – Stimmungs-Namen world.mood.<Key>
-- =====================================================================

return {
	de = {
		-- Schilder (B2)
		["world.sign.plaza"] = "CLUTCH PLAZA",
		["world.sign.duels"] = "DUELLE",
		["world.sign.ffa"] = "FFA-BRAWL",
		["world.sign.mutator"] = "MUTATOR",
		["world.sign.training"] = "TRAINING",
		["world.sign.crown"] = "KRONEN-RING",
		["world.sign.challengers"] = "HERAUSFORDERER",
		["world.sign.shop"] = "SHOP",
		["world.sign.locker"] = "SPIND",
		["world.sign.pass"] = "CLUTCH PASS",
		["world.sign.quests"] = "QUESTS",
		["world.sign.daily"] = "TÄGLICH",
		["world.sign.crates"] = "KISTEN",
		["world.sign.vip"] = "VIP",
		["world.sign.vipOnly"] = "NUR VIP",
		["world.sign.botBooth"] = "GEGEN BOTS ÜBEN",
		["world.sign.rack"] = "WAFFEN-REGAL",
		["world.sign.lane"] = "BAHN %d",
		["world.sign.distance"] = "%d STUDS",
		["world.sign.welcome"] = "WILLKOMMEN!",

		-- Bestenlisten-Tafeln (B16.9)
		["world.board.Wins"] = "SIEGE",
		["world.board.Elims"] = "POPS",
		["world.board.BestStreak"] = "BESTE SERIE",
		["world.board.TotalXP"] = "GESAMT-XP",
		["world.board.WeeklyWins"] = "SIEGE DER WOCHE",
		["world.board.CrownBest"] = "KRONEN-REKORD",

		-- Königs-Tafel (Crown Ring)
		["world.crown.king"] = "KÖNIG",
		["world.crown.streak"] = "SERIE",
		["world.crown.empty"] = "THRON FREI!",

		-- Prompts (ProximityPrompt)
		["world.prompt.open"] = "Öffnen",
		["world.prompt.practice"] = "Üben",

		-- Bot-Stufen in der Bot-Duell-Kabine
		["world.diff.Easy"] = "LEICHT",
		["world.diff.Normal"] = "NORMAL",
		["world.diff.Hard"] = "SCHWER",
		["world.diff.Insane"] = "WAHNSINN",

		-- Licht-Stimmungen (B8.2)
		["world.mood.Day"] = "Tag",
		["world.mood.Sunset"] = "Sonnenuntergang",
		["world.mood.NeonNight"] = "Neon-Nacht",
		["world.mood.Fog"] = "Nebel",
		["world.mood.Snowy"] = "Schnee",
	},
	en = {
		["world.sign.plaza"] = "CLUTCH PLAZA",
		["world.sign.duels"] = "DUELS",
		["world.sign.ffa"] = "FFA BRAWL",
		["world.sign.mutator"] = "MUTATOR",
		["world.sign.training"] = "TRAINING",
		["world.sign.crown"] = "CROWN RING",
		["world.sign.challengers"] = "CHALLENGERS",
		["world.sign.shop"] = "SHOP",
		["world.sign.locker"] = "LOCKER",
		["world.sign.pass"] = "CLUTCH PASS",
		["world.sign.quests"] = "QUESTS",
		["world.sign.daily"] = "DAILY",
		["world.sign.crates"] = "CRATES",
		["world.sign.vip"] = "VIP",
		["world.sign.vipOnly"] = "VIP ONLY",
		["world.sign.botBooth"] = "PRACTICE VS BOTS",
		["world.sign.rack"] = "WEAPON RACK",
		["world.sign.lane"] = "LANE %d",
		["world.sign.distance"] = "%d STUDS",
		["world.sign.welcome"] = "WELCOME!",

		["world.board.Wins"] = "WINS",
		["world.board.Elims"] = "POPS",
		["world.board.BestStreak"] = "BEST STREAK",
		["world.board.TotalXP"] = "TOTAL XP",
		["world.board.WeeklyWins"] = "WEEKLY WINS",
		["world.board.CrownBest"] = "CROWN RECORD",

		["world.crown.king"] = "KING",
		["world.crown.streak"] = "STREAK",
		["world.crown.empty"] = "THRONE OPEN!",

		["world.prompt.open"] = "Open",
		["world.prompt.practice"] = "Practice",

		["world.diff.Easy"] = "EASY",
		["world.diff.Normal"] = "NORMAL",
		["world.diff.Hard"] = "HARD",
		["world.diff.Insane"] = "INSANE",

		["world.mood.Day"] = "Day",
		["world.mood.Sunset"] = "Sunset",
		["world.mood.NeonNight"] = "Neon Night",
		["world.mood.Fog"] = "Fog",
		["world.mood.Snowy"] = "Snowy",
	},
}
