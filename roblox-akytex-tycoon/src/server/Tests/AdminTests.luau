-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Admin, Events, Anti-Cheat (Server/Tests/AdminTests)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §D WP11 "Tests" + §C17 (SelfTestService lädt dieses
--  Modul). Gibt { [testName]: (Services) -> () } zurück; jeder Fehler = FAIL.
--  Prüft: Owner-Regel in allen Varianten (Nutzer-/Gruppen-Spiel, Studio, Player2 nie), Klemmen ALLER Katalog-Parameter
--  (Markt + Nicht-Markt), globale Nachricht mit zu großem Until verworfen (AdminService.Core + EventService.ApplyGlobal),
--  Rolle in Ansage/AbuseNote (W19: fehlt = Owner, unbekannt = verworfen), Dedupe per Id, Besitzer-Handelssperre/
--  Taint-Fenster ±120 s, Katalog = 21 Events mit Texten, Event-Belohnungs-Quellen in der CR-Whitelist,
--  Config.Events.Validate leer, Anti-Cheat-Guards (present) ohne Spieler.
--  Team-Rollen (W19/W26): jede Admin-Aktion hat ein Recht aus Shared/Staff.PERMS (Core.PermFor, Spot-Checks §5.2/§16.1),
--  Tor-Hilfen rein (Masse > 3 Ziele, unbekannter Besitzer sperrt strafende Rechte, Schwer-Abstand, keine Selbstgeschenke,
--  CR-Deckel, Bann-Dauer), Run/SubmitReport/Dismiss ohne echten Spieler abgelehnt.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Clock = require(Shared:WaitForChild("Clock"))
local Staff = require(Shared:WaitForChild("Staff"))

local EV: any = Config.Events

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label .. " erwartet wahr", 2)
	end
end

local function falsy(value: any, label: string)
	if value then
		error(label .. " erwartet falsch/nil", 2)
	end
end

-- Dienst aus der Services-Tabelle (SelfTestService) oder direkt aus dem Ordner
local function serviceOf(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local folder = script.Parent.Parent:FindFirstChild("Services")
	local module = folder and folder:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

local Tests = {}

-- ---------------------------------------------------------------------
-- 1) OWNER-REGEL (§B15.1)
-- ---------------------------------------------------------------------
Tests["Admin: Owner-Regel (Nutzer-Spiel, Gruppen-Spiel, Studio, Player2 nie)"] = function(services: any)
	local Core = serviceOf(services, "AdminService").Core
	local cfg = { OwnerIsAdmin = true, GroupOwnerIsAdmin = true, StudioIsAdmin = true, StudioAllPlayersAdmin = false }
	local function rule(info: { [string]: any }): boolean
		info.Cfg = info.Cfg or cfg
		return Core.OwnerRule(info)
	end
	-- Nutzer-Spiel
	truthy(rule({ CreatorType = "User", CreatorId = 555, UserId = 555, Studio = false }), "Besitzer live")
	falsy(rule({ CreatorType = "User", CreatorId = 555, UserId = 556, Studio = false }), "fremder Spieler live")
	falsy(rule({ CreatorType = "User", CreatorId = 0, UserId = 0, Studio = false }), "CreatorId 0 nie Admin")
	falsy(
		rule({
			CreatorType = "User",
			CreatorId = 555,
			UserId = 555,
			Studio = false,
			Cfg = { OwnerIsAdmin = false, StudioIsAdmin = true },
		}),
		"OwnerIsAdmin = false"
	)
	-- Gruppen-Spiel (GetGroupInfoAsync-Ergebnis, Fehler = kein Admin)
	truthy(
		rule({ CreatorType = "Group", CreatorId = 99, UserId = 777, GroupOwnerId = 777, Studio = false }),
		"Gruppen-Besitzer"
	)
	falsy(
		rule({ CreatorType = "Group", CreatorId = 99, UserId = 778, GroupOwnerId = 777, Studio = false }),
		"Gruppen-Mitglied"
	)
	falsy(
		rule({ CreatorType = "Group", CreatorId = 99, UserId = 777, GroupOwnerId = nil, Studio = false }),
		"Gruppen-Info fehlt"
	)
	falsy(rule({ CreatorType = "Group", CreatorId = 99, UserId = 99, Studio = false }), "Gruppen-Id ist kein Nutzer")
	falsy(
		rule({
			CreatorType = "Group",
			CreatorId = 99,
			UserId = 777,
			GroupOwnerId = 777,
			Studio = false,
			Cfg = { GroupOwnerIsAdmin = false },
		}),
		"GroupOwnerIsAdmin = false"
	)
	-- Studio: Player1 (-1) ja, eigene Id ja, Player2 (-2) NIE
	truthy(rule({ CreatorType = "User", CreatorId = 0, UserId = -1, Studio = true }), "Studio Player1")
	truthy(rule({ CreatorType = "User", CreatorId = 0, UserId = 12345, Studio = true }), "Studio eigener Account")
	falsy(rule({ CreatorType = "User", CreatorId = 0, UserId = -2, Studio = true }), "Studio Player2")
	falsy(
		rule({
			CreatorType = "User",
			CreatorId = 0,
			UserId = -2,
			Studio = true,
			Cfg = { StudioIsAdmin = true, StudioAllPlayersAdmin = true },
		}),
		"Player2 auch mit StudioAllPlayersAdmin nie"
	)
	truthy(
		rule({
			CreatorType = "User",
			CreatorId = 0,
			UserId = -3,
			Studio = true,
			Cfg = { StudioIsAdmin = true, StudioAllPlayersAdmin = true },
		}),
		"Player3 nur mit StudioAllPlayersAdmin"
	)
	falsy(rule({ CreatorType = "User", CreatorId = 0, UserId = -3, Studio = true }), "Player3 sonst nie")
	falsy(
		rule({ CreatorType = "User", CreatorId = 0, UserId = -1, Studio = true, Cfg = { StudioIsAdmin = false } }),
		"StudioIsAdmin = false"
	)
	falsy(rule({ CreatorType = "User", CreatorId = 0, UserId = -1, Studio = false }), "-1 live nie Admin")
	falsy(rule({ CreatorType = "User", CreatorId = 555, UserId = 0 / 0, Studio = false }), "NaN-UserId")
	-- Projekt-Einstellung: Player2 bleibt testbar
	eq(Config.Admin.StudioAllPlayersAdmin, false, "Config.Admin.StudioAllPlayersAdmin")
end

-- ---------------------------------------------------------------------
-- 2) KLEMMEN ALLER PARAMETER (§B15.3)
-- ---------------------------------------------------------------------
Tests["Admin: Markt-Parameter geklemmt (Crash/Rally/Pump/Dump/News/Halt/Resume/IPO/Vol/Normalize)"] = function(
	services: any
)
	local Core = serviceOf(services, "AdminService").Core
	local limits = EV.AdminLimits
	-- Crash: alle Grenzen
	local action, args =
		Core.MarketArgs("MegaCrash", { Scope = "All", Strength = 999, Ramp = 1, Decay = 0, Warn = true })
	eq(action, "Crash", "MegaCrash -> Crash")
	eq(args.Strength, limits.MarketStrength[2], "Stärke oben")
	eq(args.Ramp, limits.Ramp[1], "Rampe unten")
	eq(args.Decay, limits.DecayMinutes[1], "Abklingen unten")
	eq(args.Warn, true, "Warnung")
	_, args = Core.MarketArgs("MegaRally", { Scope = "All", Strength = 1, Ramp = 99999, Decay = 99999, Warn = true })
	eq(args.Strength, limits.MarketStrength[1], "Stärke unten")
	eq(args.Ramp, limits.Ramp[2], "Rampe oben")
	eq(args.Decay, limits.DecayMinutes[2], "Abklingen oben")
	eq(args.Warn, nil, "Warnung nur beim Crash")
	_, args = Core.MarketArgs("MegaRally", { Scope = "Sector", Target = "E", Strength = 0 / 0 })
	eq(args.Scope, "Sector", "Sektor")
	eq(args.Strength, limits.MarketStrength[1], "NaN -> Untergrenze")
	local bad, _, errKey = Core.MarketArgs("MegaCrash", { Scope = "Sector", Target = "X" })
	eq(bad, nil, "unbekannter Sektor")
	eq(errKey, "admin.badScope", "Fehler-Schlüssel")
	bad = Core.MarketArgs("MegaCrash", { Scope = "Inst", Target = 1.5 })
	eq(bad, nil, "Instrument nicht ganzzahlig")
	-- Pump/Dump
	_, args = Core.MarketArgs("Pump", { Target = 7, Strength = 80 })
	eq(args.Target, 7, "Pump-Ziel")
	eq(args.Strength, limits.MarketStrength[2], "Pump oben")
	bad = Core.MarketArgs("Dump", { Strength = 10 })
	eq(bad, nil, "Dump ohne Ziel")
	-- News: Text ≤ 80, Band 1 … 4, Richtung ±1
	local long = string.rep("A", (limits.NewsChars or 80) + 1)
	bad = Core.MarketArgs("News", { Scope = "Inst", Target = 3, Text = { de = long, en = "x" } })
	eq(bad, nil, "Eilmeldung zu lang")
	_, args = Core.MarketArgs("News", { Scope = "Sector", Target = "T", Band = 9, Dir = -5, Text = { de = "Test" } })
	eq(args.Band, limits.NewsBand[2], "Band oben")
	eq(args.Dir, -1, "Richtung")
	eq(args.Text.en, "Test", "EN fällt auf DE zurück")
	bad = Core.MarketArgs("News", { Scope = "All", Text = { de = "x", en = "y" } })
	eq(bad, nil, "Eilmeldung nur Wert/Sektor")
	-- Halt/Resume
	_, args = Core.MarketArgs("Halt", { Seconds = 1 })
	eq(args.Seconds, limits.HaltSeconds[1], "Pause unten")
	eq(args.Scope, "All", "Pause ganzer Markt")
	_, args = Core.MarketArgs("Halt", { Scope = "Inst", Target = 5, Seconds = 99999 })
	eq(args.Seconds, limits.HaltSeconds[2], "Pause oben")
	_, args = Core.MarketArgs("Resume", {})
	eq(args.Scope, "All", "Weiter")
	-- IPO
	bad = Core.MarketArgs("Ipo", {})
	eq(bad, nil, "IPO ohne Firma")
	_, args = Core.MarketArgs("Ipo", { Target = 100 })
	eq(args.Target, 100, "IPO-Ziel")
	-- Volatilität ×0,5 … ×3, 5 … 30 min
	_, args = Core.MarketArgs("Vol", { Strength = 10, Minutes = 100 })
	eq(args.Strength, limits.Vol[2], "Vol oben")
	eq(args.Minutes, limits.VolMinutes[2], "Vol-Minuten oben")
	_, args = Core.MarketArgs("Vol", { Strength = 0.01, Minutes = 0 })
	eq(args.Strength, limits.Vol[1], "Vol unten")
	eq(args.Minutes, limits.VolMinutes[1], "Vol-Minuten unten")
	-- Normalisieren, Unbekanntes
	action = Core.MarketArgs("Normalize", { Junk = true })
	eq(action, "Normalize", "Normalisieren")
	bad, _, errKey = Core.MarketArgs("MoonShot", {})
	eq(bad, nil, "unbekannte Markt-Aktion")
	eq(errKey, "admin.evUnknown", "Fehler-Schlüssel unbekannt")
end

Tests["Admin: Nicht-Markt-Parameter geklemmt (Geldregen, Golden Hour, XP-Rausch, Boss, Show)"] = function(services: any)
	local EventService = serviceOf(services, "EventService")
	local limits = EV.AdminLimits
	local args = EventService.Clamp("MoneyRain", { Seconds = 1 })
	eq(args.Seconds, limits.MoneyRain.Seconds[1], "Geldregen unten")
	args = EventService.Clamp("MoneyRain", { Seconds = 99999 })
	eq(args.Seconds, limits.MoneyRain.Seconds[2], "Geldregen oben")
	args = EventService.Clamp("GoldenHour", { Mult = 99, Minutes = 999 })
	eq(args.Mult, 3, "Golden Hour ×3 oben")
	eq(args.Minutes, limits.GoldenHour.Minutes[2], "Golden-Hour-Minuten oben")
	args = EventService.Clamp("GoldenHour", { Mult = 1, Minutes = 0 })
	eq(args.Mult, 2, "Golden Hour ×2 unten")
	eq(args.Minutes, limits.GoldenHour.Minutes[1], "Golden-Hour-Minuten unten")
	args = EventService.Clamp("GoldenHour", { Mult = 2.4 })
	eq(args.Mult, 2, "nur ×2 oder ×3")
	args = EventService.Clamp("XpRush", { Minutes = 1 })
	eq(args.Minutes, limits.XpRush.Minutes[1], "XP-Rausch unten")
	args = EventService.Clamp("XpRush", { Minutes = 1000 })
	eq(args.Minutes, limits.XpRush.Minutes[2], "XP-Rausch oben")
	args = EventService.Clamp("Boss", { Seconds = 5 })
	eq(args.Seconds, limits.Boss.Seconds[1], "Boss unten")
	args = EventService.Clamp("Boss", { Seconds = 1e9 })
	eq(args.Seconds, limits.Boss.Seconds[2], "Boss oben")
	args = EventService.Clamp("SaturdayShow", { GoldenMult = 99 })
	eq(args.GoldenMult, limits.SaturdayShow.GoldenMult, "Show-Werte kommen nur aus der Config")
	local none, errKey = EventService.Clamp("Nuke", {})
	eq(none, nil, "unbekanntes Event")
	eq(errKey, "admin.evUnknown", "Fehler-Schlüssel")
	-- jeder Nicht-Markt-Katalog-Eintrag ist startbar, jeder Markt-Eintrag hat eine Markt-Aktion
	local Core = serviceOf(services, "AdminService").Core
	for _, entry in ipairs(EV.Catalogue) do
		if entry.Market then
			local action = Core.MarketArgs(entry.Key, {
				Scope = "Inst",
				Target = 3,
				Strength = 10,
				Text = { de = "Test", en = "Test" },
			})
			truthy(action, "Markt-Aktion für " .. entry.Key)
		else
			local kind = if entry.Key == "BuildBoom" then "AdminBuildBoom" else entry.Key
			truthy(EventService.Clamp(kind, {}), "Nicht-Markt-Event startbar: " .. entry.Key)
		end
	end
end

-- ---------------------------------------------------------------------
-- 3) GLOBALE NACHRICHTEN (obere Zeitgrenze, Dedupe)
-- ---------------------------------------------------------------------
Tests["Admin: globale Nachricht mit zu großem Until verworfen, Felder geprüft"] = function(services: any)
	local Core = serviceOf(services, "AdminService").Core
	local now = 1800000000
	local max = EV.MaxGlobalSeconds
	local base =
		{ Kind = "AdminAbuse", Id = "A123456", Event = "GoldenHour", Args = { Mult = 2, Minutes = 10 }, By = 1 }
	local function msg(startAt: number, untilT: number): { [string]: any }
		local m = table.clone(base)
		m.StartAt = startAt
		m.Until = untilT
		return m
	end
	truthy(Core.ValidateGlobal(msg(now + 5, now + 605), now, max), "gültig")
	falsy(Core.ValidateGlobal(msg(now + 5, now + max + 1), now, max), "Until > now + max")
	falsy(Core.ValidateGlobal(msg(now - 10, now - 1), now, max), "Until schon vorbei")
	falsy(Core.ValidateGlobal(msg(now + 700, now + 600), now, max), "StartAt nach Until")
	falsy(Core.ValidateGlobal(msg(0 / 0, now + 600), now, max), "StartAt NaN")
	local noId = msg(now, now + 60)
	noId.Id = nil
	falsy(Core.ValidateGlobal(noId, now, max), "ohne Id")
	local deep = msg(now, now + 60)
	deep.Args = { Mult = { Evil = true }, Minutes = 10 }
	local cleaned = Core.ValidateGlobal(deep, now, max)
	truthy(cleaned, "Tabellen in Args werden entfernt, Rest bleibt")
	eq(cleaned.Args.Mult, nil, "verschachtelte Tabelle verworfen")
	eq(cleaned.Args.Minutes, 10, "Zahl bleibt")
	truthy(
		Core.ValidateGlobal({ Kind = "Announce", Id = "N1234", Text = "Hallo", Name = "Owner", UserId = 1 }, now, max),
		"Ansage gültig"
	)
	falsy(
		Core.ValidateGlobal({ Kind = "Announce", Id = "N1234", Text = "", Name = "Owner", UserId = 1 }, now, max),
		"leere Ansage"
	)
	falsy(
		Core.ValidateGlobal({ Kind = "Announce", Id = "N1234", Text = "x", Name = "O", UserId = 1.5 }, now, max),
		"UserId ganzzahlig"
	)
	falsy(Core.ValidateGlobal({ Kind = "Unknown", Id = "X1234" }, now, max), "unbekannte Art")
	truthy(Core.ValidateGlobal({ Kind = "Live", Id = "L1234", Version = 3 }, now, max), "Live")
	falsy(Core.ValidateGlobal("Text", now, max), "kein Table")
	-- Besitzer-Ansage zu Admin-Abuse-Events (Avatar + Haken): nur Katalog-artige Namen, Name/UserId geprüft
	truthy(
		Core.ValidateGlobal(
			{ Kind = "AbuseNote", Id = "B1234", Event = "MegaCrash", UserId = 1, Name = "Owner" },
			now,
			max
		),
		"AbuseNote gültig"
	)
	falsy(
		Core.ValidateGlobal(
			{ Kind = "AbuseNote", Id = "B1234", Event = "Mega Crash!", UserId = 1, Name = "Owner" },
			now,
			max
		),
		"AbuseNote: Event nur Buchstaben/Ziffern"
	)
	falsy(
		Core.ValidateGlobal({ Kind = "AbuseNote", Id = "B1234", Event = "MegaCrash", UserId = 1 }, now, max),
		"AbuseNote ohne Name"
	)
	-- W19: Rolle des Absenders (fehlt = "Owner" für ältere Server, nur Staff.ROLES, sonst verworfen)
	local announce = { Kind = "Announce", Id = "N1234", Text = "Hallo", Name = "Team", UserId = 1 }
	local withRole: { [string]: any } = table.clone(announce)
	withRole.Role = "Admin"
	eq((Core.ValidateGlobal(withRole, now, max) or {}).Role, "Admin", "Ansage mit Rolle Admin")
	eq((Core.ValidateGlobal(announce, now, max) or {}).Role, "Owner", "Ansage ohne Rolle = Owner")
	local badRole: { [string]: any } = table.clone(announce)
	badRole.Role = "Boss"
	falsy(Core.ValidateGlobal(badRole, now, max), "Ansage mit unbekannter Rolle verworfen")
	badRole.Role = 3
	falsy(Core.ValidateGlobal(badRole, now, max), "Ansage mit Zahl als Rolle verworfen")
	local note = { Kind = "AbuseNote", Id = "B1234", Event = "Fireworks", UserId = 1, Name = "Team" }
	local noteMod: { [string]: any } = table.clone(note)
	noteMod.Role = "Moderator"
	eq((Core.ValidateGlobal(noteMod, now, max) or {}).Role, "Moderator", "AbuseNote mit Rolle")
	eq((Core.ValidateGlobal(note, now, max) or {}).Role, "Owner", "AbuseNote ohne Rolle = Owner")
	noteMod.Role = "Boss"
	falsy(Core.ValidateGlobal(noteMod, now, max), "AbuseNote mit unbekannter Rolle verworfen")
	-- EventService prüft selbst noch einmal (auch für Werte aus dem Speicher)
	local EventService = serviceOf(services, "EventService")
	local t = Clock.Now()
	eq(
		EventService.ApplyGlobal({ Event = "Confetti", Args = {}, StartAt = t + 1, Until = t + max + 60 }),
		false,
		"EventService: Until zu groß"
	)
	eq(
		EventService.ApplyGlobal({ Event = "AllToHall", Args = {}, StartAt = t + 1, Until = t + 60 }),
		false,
		"AllToHall nie global"
	)
	eq(
		EventService.ApplyGlobal({ Event = "Nope", Args = {}, StartAt = t + 1, Until = t + 60 }),
		false,
		"unbekanntes Event"
	)
end

Tests["Admin: Dedupe per Id (letzte n)"] = function(services: any)
	local Core = serviceOf(services, "AdminService").Core
	local dedupe = Core.NewDedupe(3)
	eq(dedupe.Seen("a"), false, "erste Nachricht")
	eq(dedupe.Seen("a"), true, "Duplikat verworfen")
	dedupe.Seen("b")
	dedupe.Seen("c")
	dedupe.Seen("d") -- "a" fällt heraus
	eq(dedupe.Size(), 3, "begrenzt")
	eq(dedupe.Seen("a"), false, "alte Id nach Verdrängung wieder neu")
	eq(dedupe.Seen("d"), true, "jüngste Id bleibt")
	eq(EV.GlobalDedupe >= 200, true, "Dedupe der letzten 200 (§C13)")
end

-- ---------------------------------------------------------------------
-- 4) TAINT-FENSTER / BESITZER-HANDELSSPERRE (±120 s)
-- ---------------------------------------------------------------------
Tests["Admin: Taint-Fenster ±120 s um eigene Markt-Events"] = function(services: any)
	local Core = serviceOf(services, "AdminService").Core
	local block = Config.Security.OwnerTradeBlockSeconds
	eq(block, 120, "OwnerTradeBlockSeconds")
	local list = { { Issued = 1000, Start = 1010 } }
	falsy(Core.TradeBlocked(list, 990, block), "vor dem Auslösen frei")
	truthy(Core.TradeBlocked(list, 1000, block), "ab dem Auslösen gesperrt")
	truthy(Core.TradeBlocked(list, 1010 + block, block), "bis +120 s nach dem Start")
	falsy(Core.TradeBlocked(list, 1011 + block, block), "danach frei")
	falsy(Core.TradeBlocked({}, 1000, block), "ohne Events frei")
	truthy(Core.TradeLockBefore(1000, 1000 + block - 1, block), "Handel < 120 s vorher -> Event abgelehnt")
	falsy(Core.TradeLockBefore(1000, 1000 + block, block), "Handel ≥ 120 s vorher -> erlaubt")
	falsy(Core.TradeLockBefore(nil, 1000, block), "nie gehandelt")
	-- Admin-Fenster (Liga-Taint) laufen über den Markt: bis +10 min nach dem Abklingen
	local window = Config.Market and Config.Market.Admin and Config.Market.Admin.WindowAfter
	eq(window, 600, "Admin-Fenster +10 min (Config.Market.Admin.WindowAfter)")
end

-- ---------------------------------------------------------------------
-- 5) KATALOG, TEXTE, FIREWALL, CONFIG
-- ---------------------------------------------------------------------
Tests["Admin: Katalog 21 Events mit DE/EN-Texten, Pflicht-Schlüssel"] = function()
	eq(#EV.Catalogue, 21, "Admin-Abuse-Katalog")
	local market, other = 0, 0
	for _, entry in ipairs(EV.Catalogue) do
		if entry.Market then
			market += 1
		else
			other += 1
		end
		truthy(Lang.Has("admin.ev." .. entry.Key), "Text admin.ev." .. entry.Key)
		truthy(Lang.Has("admin.evHint." .. entry.Key), "Hinweis admin.evHint." .. entry.Key)
	end
	eq(market, 10, "Markt-Events")
	eq(other, 11, "Nicht-Markt-Events")
	for _, key in ipairs({ "evt.adminWindow", "admin.denied", "admin.acKick", "admin.acBanReason", "evt.pickupFar" }) do
		truthy(Lang.Has(key), "Pflicht-Schlüssel " .. key)
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, "DE/EN " .. key)
	end
	for _, kind in ipairs(EV.Rotation) do
		truthy(Lang.Has("evt.worldStart." .. kind), "Welt-Event-Text " .. kind)
	end
	-- jede Katalog-Aktion hat eine Besitzer-Ansage (DE + EN), dazu Geschenke an alle
	for _, entry in ipairs(EV.Catalogue) do
		local key = "admin.note." .. entry.Key
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, "Ansage DE/EN " .. key)
	end
	for _, key in ipairs({ "admin.note.Generic", "admin.note.SpeedGift", "admin.note.MoneyGift" }) do
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, "Ansage DE/EN " .. key)
	end
end

Tests["Admin: Speed-Geschenk 16–200 (Wunsch 18) und Anti-Cheat-Spielraum"] = function()
	local powers = Config.Security.Powers
	eq(powers.Speed.Min, 16, "Tempo ab 16")
	truthy(powers.Speed.Max >= 200, "Tempo bis mindestens 200")
	truthy(powers.Jump.Max >= 50, "Sprungkraft-Regler")
	truthy(powers.GiftMaxMinutes >= 60, "Geschenk bis mindestens 60 min")
	-- das höchste Geschenk bleibt unter der absoluten Anti-Cheat-Obergrenze (600 Studs/s)
	local sec = Config.Security
	truthy(powers.Speed.Max * sec.SpeedTolerance + sec.SpeedSlack < 600, "Geschenk-Tempo < Anti-Cheat-Deckel")
	for _, key in ipairs({ "admin.giftGot", "admin.giftGotOpen", "admin.giftEnded", "admin.giftGiven" }) do
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, "DE/EN " .. key)
	end
end

Tests["Events: Belohnungen nur über CR-Whitelist (Firewall), Config gültig"] = function()
	local sources: { [string]: boolean } = {}
	for _, name in ipairs(Config.Shop.Sources or {}) do
		sources[name] = true
	end
	for _, source in ipairs({ "Pickup", "Rain", "Event", "Admin" }) do
		truthy(sources[source], "CR-Quelle " .. source .. " in Config.Shop.Sources")
	end
	local errors = EV.Validate(Config)
	eq(#errors, 0, "Config.Events.Validate: " .. table.concat(errors, " | "))
	truthy(EV.RainCoinsMax <= 30, "Geldregen max. 30 je Spieler")
	truthy(EV.PickupRange <= 12, "Pickup-Abstand ≤ 12 Studs")
	truthy(EV.MaxGlobalSeconds <= 3600, "MaxGlobalSeconds ≤ 3600")
	truthy(EV.PickupMaxPerPlayer <= 60, "Pickup-Token ≤ 60 je Spieler (§C16)")
	eq(type(EV.BoostPause), "boolean", "Notschalter BoostPause vorhanden (LiveFields)")
end

Tests["Events: Rotation, nächstes Welt-Event und Wochen-Termine deterministisch"] = function(services: any)
	local EventService = serviceOf(services, "EventService")
	-- Abfragen dürfen ohne Spieler nicht scheitern und liefern nie nil
	local active = EventService.Active()
	eq(type(active), "table", "Active()")
	local mult = EventService.EventMult()
	truthy(mult >= 1 and mult <= 3, "EventMult im Bereich 1 … 3")
	eq(type(EventService.IsAdminAbuse()), "boolean", "IsAdminAbuse")
	eq(type(EventService.BearActive()), "boolean", "BearActive")
	-- Berlin-Termine liegen für alle Server gleich (Samstags-Show 18:15)
	local after = 1791892800 -- Mo 2026-10-12 12:00 UTC
	local show = Clock.NextBerlin(6, 18, 15, after)
	eq(Clock.Weekday(show + Clock.BerlinOffset(show)), 6, "Samstag (Berlin)")
	eq(((show + Clock.BerlinOffset(show)) % 86400), 18 * 3600 + 15 * 60, "18:15 Berlin")
end

-- ---------------------------------------------------------------------
-- 5b) TEAM-ROLLEN (W19/W26): ein Tor, ein Recht je Aktion, reine Tor-Hilfen
-- ---------------------------------------------------------------------
Tests["Admin: jede Aktion hat ein Recht aus Staff.PERMS (Core.PermFor, §5.2/§16.1)"] = function(services: any)
	local Core = serviceOf(services, "AdminService").Core
	local cfg = Config.Security.Staff
	local perms: { [string]: boolean } = {}
	for _, perm in ipairs(Staff.PERMS) do
		perms[perm] = true
	end
	local names = Core.ActionNames()
	truthy(#names >= 55, "mindestens 55 Admin-Aktionen")
	for _, name in ipairs(names) do
		local perm = Core.PermFor(name, {}, cfg)
		truthy(perm ~= nil and perms[perm], "Recht für Aktion " .. name)
	end
	for _, name in ipairs({ "Mute", "Unmute", "SetRole", "StaffList", "ResolveReport", "Respawn", "TpTo", "Shutdown" }) do
		truthy(table.find(names, name), "neue Aktion " .. name)
	end
	local function perm(action: string, args: { [string]: any }?): string?
		return Core.PermFor(action, args or {}, cfg)
	end
	eq(perm("Unban"), "UnbanOwn", "Unban -> UnbanOwn (Handler prüft Staff.CanUnban)")
	eq(perm("Bans"), "BanView", "Bans -> BanView")
	eq(perm("Ban", { Duration = "1d" }), "TempBan", "Bann 1 Tag = Zeit-Bann")
	eq(perm("Ban", { Duration = "30m" }), "TempBan", "Bann 30 min = Zeit-Bann")
	eq(perm("Ban", { Seconds = 3600 }), "TempBan", "Bann per Sekunden")
	eq(perm("Ban", { Duration = "7d" }), "Ban", "Bann 7 Tage = volles Bann-Recht")
	eq(perm("Ban", { Duration = "perm" }), "Ban", "Dauer-Bann = volles Bann-Recht")
	eq(perm("Ban", { UserId = 5, Duration = "1h" }), "Ban", "offline per UserId = volles Bann-Recht")
	eq(perm("Ban", { Name = "Someone", Duration = "1h" }), "Ban", "offline per Name = volles Bann-Recht")
	eq(perm("Give", { Grant = { Credits = 5 } }), "GiveCredits", "CR geben")
	eq(perm("Give", { Grant = { Credits = -5 } }), "TakeCredits", "CR abziehen")
	eq(perm("Give", { Grant = { Cars = { "x" } } }), "GiveItems", "Items")
	eq(perm("Give", { Grant = { Credits = 5, Junk = true } }), "GiveItems", "unbekannte Felder = Besitzer-Recht")
	eq(perm("Abuse", { Event = "MegaRally" }), "MarketEvents", "Markt-Event")
	eq(perm("Abuse", { Event = "Fireworks" }), "FunEvents", "Spaß-Event")
	eq(perm("Abuse", { Event = "GoldenHour" }), "EconomyEvents", "Wirtschafts-Event")
	eq(perm("Abuse", { Event = "SaturdayShow" }), "MarketEvents", "Samstags-Show (mit Markt-Rally)")
	eq(perm("Abuse", { Event = "Gibtsnicht" }), "EconomyEvents", "unbekanntes Event = Besitzer-Recht")
	eq(perm("WorldEvent", { Event = "Truck" }), "WorldEvents", "Welt-Event")
	eq(perm("WorldEvent", { Event = "BuildBoom" }), "EconomyEvents", "Welt-Bau-Boom = Wirtschaft")
	eq(perm("SetPower", { Name = "AdminESP" }), "Esp", "ESP")
	eq(perm("SetPower", { Name = "CanFly" }), "Fly", "Fliegen")
	eq(perm("SetPower", { Name = "Gibtsnicht" }), "Debug", "unbekannte Kraft = Debug")
	eq(perm("SetRole", { Role = "Admin" }), "ManageAdmins", "Admin vergeben")
	eq(perm("SetRole", { Role = "Moderator" }), "ManageMods", "Moderator vergeben")
	eq(perm("SetRole", { Role = "" }), "ManageMods", "Rolle entfernen")
	eq(perm("Announce", { Global = true }), "AnnounceGlobal", "globale Ansage")
	eq(perm("Announce"), "Announce", "lokale Ansage")
	eq(perm("TpTo"), "Bring", "TpTo = Herholen")
	eq(perm("Gibtsnicht"), nil, "unbekannte Aktion = kein Recht")
	eq(Core.PermFor(nil, {}, cfg), nil, "keine Aktion = kein Recht")
	-- Matrix gegen die echte Config (Moderator: Zeit-Bann ja, 7 Tage nein; Admin: kein Abziehen, keine Markt-Events)
	truthy(Staff.Can("Moderator", perm("Ban", { Duration = "1d" }) :: string, cfg), "Moderator: Zeit-Bann")
	falsy(Staff.Can("Moderator", perm("Ban", { Duration = "7d" }) :: string, cfg), "Moderator: 7 Tage nie")
	truthy(Staff.Can("Moderator", perm("Unban") :: string, cfg), "Moderator: /unban (nur eigene, Handler)")
	falsy(Staff.Can("Admin", perm("Give", { Grant = { Credits = -5 } }) :: string, cfg), "Admin: CR abziehen nie")
	falsy(Staff.Can("Admin", perm("Market") :: string, cfg), "Admin: Markt-Events nie")
	falsy(Staff.Can("Admin", perm("LiveSet") :: string, cfg), "Admin: Live-Config nie")
	truthy(Staff.Can("Owner", perm("Shutdown") :: string, cfg), "Besitzer: Neustart")
	-- Schwere Lese-Aktionen und strafende Rechte zeigen auf echte Aktionen/Rechte
	for action in pairs(Core.HEAVY) do
		truthy(table.find(names, action), "HEAVY-Aktion existiert: " .. action)
	end
	for permName in pairs(Core.PUNITIVE) do
		truthy(perms[permName], "strafendes Recht existiert: " .. permName)
	end
end

Tests["Admin: Tor-Hilfen rein (Masse, Besitzer unbekannt, Abstand, Selbstgeschenk, CR-Deckel, Bann-Dauer)"] = function(
	services: any
)
	local Core = serviceOf(services, "AdminService").Core
	-- Masse: all/others oder mehr als 3 aufgelöste Ziele (§16.2 Nr. 8)
	truthy(Core.IsMassList("all", 1), "all = Masse")
	truthy(Core.IsMassList(" Others ", 0), "others = Masse")
	falsy(Core.IsMassList("a,b,c", 3), "3 Ziele sind keine Masse")
	truthy(Core.IsMassList("a,b,c,d", 4), "4 Ziele = Masse")
	falsy(Core.IsMassList("bob", 1), "ein Ziel")
	-- Unbekannter Gruppen-Besitzer sperrt strafende Rechte für alle außer dem Besitzer (§16.2 Nr. 1)
	truthy(Core.OwnerBlocks("Kick", false, false), "Kick bei unbekanntem Besitzer gesperrt")
	truthy(Core.OwnerBlocks("TempBan", false, false), "Zeit-Bann gesperrt")
	truthy(Core.OwnerBlocks("ManageAdmins", false, false), "Rollen gesperrt")
	falsy(Core.OwnerBlocks("Kick", true, false), "Besitzer selbst darf")
	falsy(Core.OwnerBlocks("Kick", false, true), "bekannter Besitzer: frei")
	falsy(Core.OwnerBlocks("Teleport", false, false), "nicht strafend: frei")
	falsy(Core.OwnerBlocks(nil, false, false), "kein Recht: nichts")
	-- Abstand je Schlüssel (Schwer-Aktionen 3 s, Ansagen, Ablehnungs-Log)
	local store: { [string]: number } = {}
	local ok, left = Core.GapOk(store, "AdminLog", 100, 3)
	truthy(ok, "erster Aufruf frei")
	eq(left, 0, "kein Rest")
	ok, left = Core.GapOk(store, "AdminLog", 100.5, 3)
	falsy(ok, "zweiter Aufruf < 3 s abgelehnt")
	eq(left, 2.5, "Restzeit")
	truthy((Core.GapOk(store, "Reports", 100.5, 3)), "andere Aktion unabhängig")
	truthy((Core.GapOk(store, "AdminLog", 103, 3)), "nach 3 s wieder frei")
	-- Keine Selbstgeschenke für Nicht-Besitzer (§16.2 Nr. 6)
	local a, b = { Name = "A" }, { Name = "B" }
	eq(#Core.GiftTargets({ a, b }, a, false), 1, "sich selbst übersprungen")
	eq(Core.GiftTargets({ a, b }, a, false)[1], b, "nur der andere bleibt")
	eq(#Core.GiftTargets({ a }, a, false), 0, "nur sich selbst -> niemand")
	eq(#Core.GiftTargets({ a, b }, a, true), 2, "Besitzer unverändert")
	-- CR-Deckel je Befehl und Tag (Werte aus der Config)
	local credits = Config.Security.Staff.Credits
	truthy((Core.CreditCaps(credits.PerAction, 1, 0, credits)), "genau der Befehls-Deckel")
	local okCap, key, value = Core.CreditCaps(credits.PerAction, 2, 0, credits)
	falsy(okCap, "zwei Ziele über dem Befehls-Deckel")
	eq(key, "admin.cmd.capAction", "Schlüssel Befehls-Deckel")
	eq(value, credits.PerAction, "Betrag Befehls-Deckel")
	okCap, key, value = Core.CreditCaps(credits.PerAction, 1, credits.PerDay - credits.PerAction + 1, credits)
	falsy(okCap, "Tageslimit")
	eq(key, "admin.cmd.capDay", "Schlüssel Tageslimit")
	eq(value, credits.PerAction - 1, "noch übrig heute")
	-- Bann-Dauer: Text, Presets, Sekunden; ungültig -> nil
	eq(Core.BanSeconds({ Duration = "30d" }), 2592000, "30 Tage")
	eq(Core.BanSeconds({ Duration = "perm" }), -1, "dauerhaft")
	eq(Core.BanSeconds({ Duration = "2h" }), 7200, "2 Stunden")
	eq(Core.BanSeconds({ Seconds = -1 }), -1, "Sekunden -1 = dauerhaft")
	eq(Core.BanSeconds({ Seconds = 90.7 }), 90, "Sekunden ganzzahlig")
	eq(Core.BanSeconds({ Duration = "bald" }), nil, "Unsinn")
	eq(Core.BanSeconds({ Seconds = 0 / 0 }), nil, "NaN")
end

Tests["Admin: Run, Kräfte und Meldungen ohne echten Spieler abgelehnt"] = function(services: any)
	local AdminService = serviceOf(services, "AdminService")
	local fake: any = { Name = "Fake", UserId = 1 }
	local ok, message = AdminService.Run(fake, "Kick", { Target = "all" }, "Chat")
	eq(ok, false, "Run mit Nicht-Spieler")
	eq(message, nil, "keine Meldung an Nicht-Spieler")
	eq((AdminService.Run(nil, "Dashboard", {}, "Panel")), false, "Run ohne Spieler")
	eq(AdminService.IsOwnerId(1.5), false, "IsOwnerId nur ganze Zahlen")
	eq(type(AdminService.OwnerKnown()), "boolean", "OwnerKnown")
	eq(AdminService.Power(fake, "CanFly"), nil, "Power ohne Spieler")
	AdminService.SyncPowers(fake) -- darf ohne Spieler nicht scheitern
	local AntiCheat = serviceOf(services, "AntiCheatService")
	local reply = AntiCheat.SubmitReport(fake, 2, "Speed", "Notiz", "Chat")
	eq(type(reply), "table", "SubmitReport antwortet")
	eq(reply.Ok, false, "SubmitReport ohne Spieler abgelehnt")
	eq((AntiCheat.Dismiss(123 :: any)), false, "Dismiss nur mit Text-Id")
	local done, entry = AntiCheat.Dismiss("Test_gibtsnicht")
	eq(done, true, "Dismiss unbekannter Id")
	eq(entry, nil, "kein Eintrag entfernt")
end

-- ---------------------------------------------------------------------
-- 6) ANTI-CHEAT-GUARDS (ohne echte Spieler)
-- ---------------------------------------------------------------------
Tests["AntiCheat: Guards ohne Spieler, Gewichte"] = function(services: any)
	local AntiCheat = serviceOf(services, "AntiCheatService")
	local fake: any = { Name = "Fake" }
	AntiCheat.NoteTeleport(fake, CFrame.new())
	AntiCheat.SetAllowance(fake, { MaxSpeed = 100 })
	AntiCheat.SetAllowance(fake, nil)
	AntiCheat.Grace(fake, "Impulse", 1, 50)
	AntiCheat.Exempt(fake, 2)
	AntiCheat.Add(fake, "Speed", 5, nil)
	eq(AntiCheat.Score(fake), 0, "fremde Werte haben keinen Verdacht")
	eq(next(AntiCheat.Snapshot(fake)), nil, "Snapshot ohne Spieler leer")
	eq(type(AntiCheat.Flags()), "table", "Flags-Liste")
	local weights = Config.Security.Weights
	truthy(weights.Honeypot >= Config.Security.Kick, "Honeypot = sofort Kick")
	truthy(Config.Security.Review < Config.Security.Kick, "Prüf-Flag vor Kick")
end

return Tests
