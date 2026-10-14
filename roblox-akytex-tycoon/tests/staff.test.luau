-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Staff (Team-Rollen, Rechte, Chat-Befehle; ohne Roblox)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat) – W19/W26. Vertrag: aky3_admin_spec §12.1 Gruppen 1–13, §16.1 Gruppe 14
--  (CanUnban), §16.2 Gruppe 15 (CanUndo); zusätzlich 16 Config.Security.Staff (echte Werte + Validate mit Staff),
--  17 Lang/Team (DE/EN vollständig, Befehls-Texte, keine Doppelten mit Lang/Admin).
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/staff.test.luau
--  Bei einem Fehler endet das Skript mit error(...) -> Exit-Code ≠ 0.
-- =====================================================================

local Staff = require("../src/shared/Staff")
local Security = require("../src/shared/Config/Security")
local LangTeam = require("../src/shared/Lang/Team")
local LangAdmin = require("../src/shared/Lang/Admin")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string?)
	if not value then
		error((label or "Bedingung") .. " erwartet wahr", 2)
	end
end

local function falsy(value: any, label: string?)
	if value then
		error((label or "Bedingung") .. " erwartet falsch", 2)
	end
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

-- Standard-Matrix als Literal (Kopie von Config.Security.Staff.Perms, damit Config-Feintuning den Test nicht bricht)
local function defaultCfg(): any
	return {
		AdminCanManageMods = true,
		TempBanMax = { Moderator = 86400, Admin = -1, Owner = -1 },
		Perms = {
			Panel = "Moderator",
			PlayerList = "Moderator",
			Kick = "Moderator",
			Mute = "Moderator",
			Warn = "Moderator",
			TempBan = "Moderator",
			Teleport = "Moderator",
			Bring = "Moderator",
			Freeze = "Moderator",
			Spectate = "Moderator",
			Respawn = "Moderator",
			Reports = "Moderator",
			Logs = "Moderator",
			TeamView = "Moderator",
			UnbanOwn = "Moderator",
			BanView = "Moderator",
			Ban = "Admin",
			Unban = "Admin",
			MassTarget = "Admin",
			Fly = "Admin",
			Noclip = "Admin",
			GiveSpeed = "Admin",
			GiveCredits = "Admin",
			Announce = "Admin",
			AnnounceGlobal = "Admin",
			FunEvents = "Admin",
			WorldEvents = "Admin",
			ManageMods = "Admin",
			ShowCam = "Admin",
			ManageAdmins = "Owner",
			TakeCredits = "Owner",
			GiveItems = "Owner",
			GiveAky = "Owner",
			PlayerData = "Owner",
			Purchases = "Owner",
			MarketEvents = "Owner",
			EconomyEvents = "Owner",
			GlobalEvents = "Owner",
			LockServer = "Owner",
			Shutdown = "Owner",
			KickAll = "Owner",
			LiveConfig = "Owner",
			Stats = "Owner",
			Debug = "Owner",
			Invisible = "Owner",
			Esp = "Owner",
		},
		EventPerms = {
			Lightshow = "FunEvents",
			Fireworks = "FunEvents",
			GoldenHour = "EconomyEvents",
			SaturdayShow = "MarketEvents",
			Truck = "WorldEvents",
		},
	}
end

local function names(list: { any }): string
	local out = {}
	for _, p in ipairs(list) do
		table.insert(out, tostring(p.Name))
	end
	return table.concat(out, ",")
end

local function contains(list: { string }, needle: string): boolean
	for _, value in ipairs(list) do
		if string.find(value, needle, 1, true) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- 1) ParseDuration
-- ---------------------------------------------------------------------
check("1 ParseDuration", function()
	eq(Staff.ParseDuration("30m"), 1800, "30m")
	eq(Staff.ParseDuration("2h"), 7200, "2h")
	eq(Staff.ParseDuration("1d"), 86400, "1d")
	eq(Staff.ParseDuration("7d"), 604800, "7d")
	eq(Staff.ParseDuration("1w"), 604800, "1w")
	eq(Staff.ParseDuration(" 1D "), 86400, " 1D ")
	eq(Staff.ParseDuration("10"), 600, "10 (Minuten)")
	eq(Staff.ParseDuration("45", 1), 45, "45 Sekunden")
	eq(Staff.ParseDuration("perm"), -1, "perm")
	eq(Staff.ParseDuration("Permanent"), -1, "Permanent")
	eq(Staff.ParseDuration("dauerhaft"), -1, "dauerhaft")
	eq(Staff.ParseDuration("forever"), -1, "forever")
	eq(Staff.ParseDuration("-1"), -1, "-1")
	eq(Staff.ParseDuration("0m"), nil, "0m")
	eq(Staff.ParseDuration("abc"), nil, "abc")
	eq(Staff.ParseDuration("5x"), nil, "5x")
	eq(Staff.ParseDuration("4000d"), nil, "4000d")
	eq(Staff.ParseDuration(nil), nil, "nil")
	eq(Staff.ParseDuration(30), nil, "Zahl")
	eq(Staff.ParseDuration("30d"), 2592000, "30d (Preset)")
	eq(Staff.ParseDuration("1h"), 3600, "1h (Preset)")
	eq(Staff.ParseDuration("15 min"), 900, "15 min")
	eq(Staff.ParseDuration("2std"), 7200, "2std")
	eq(Staff.ParseDuration("3 Tage"), 259200, "3 Tage")
	eq(Staff.ParseDuration("1.5h"), nil, "Kommazahl")
	eq(Staff.ParseDuration(string.rep("9", 40)), nil, "zu lang")
end)

-- ---------------------------------------------------------------------
-- 2) ParseAmount
-- ---------------------------------------------------------------------
check("2 ParseAmount", function()
	eq(Staff.ParseAmount("5000"), 5000, "5000")
	eq(Staff.ParseAmount("25k"), 25000, "25k")
	eq(Staff.ParseAmount("1.5m"), 1500000, "1.5m")
	eq(Staff.ParseAmount("1,5m"), 1500000, "1,5m")
	eq(Staff.ParseAmount("2b"), 2e9, "2b")
	eq(Staff.ParseAmount("3t"), 3e12, "3t")
	eq(Staff.ParseAmount("-2k"), -2000, "-2k")
	eq(Staff.ParseAmount("2mio"), 2e6, "2mio")
	eq(Staff.ParseAmount("1mrd"), 1e9, "1mrd")
	eq(Staff.ParseAmount("k"), nil, "k")
	eq(Staff.ParseAmount(""), nil, "leer")
	eq(Staff.ParseAmount("1e400"), nil, "1e400")
	eq(Staff.ParseAmount("9e16"), nil, "9e16")
	eq(Staff.ParseAmount("1.15k"), 1150, "1.15k exakt (kein 1149)")
	eq(Staff.ParseAmount("1.000.000"), 1000000, "Tausender-Punkte")
	eq(Staff.ParseAmount("1,500"), 1500, "Tausender-Komma ohne Einheit")
	eq(Staff.ParseAmount("2.7"), 2, "abgeschnitten")
	eq(Staff.ParseAmount("-2.7"), -2, "zur Null hin")
	eq(Staff.ParseAmount("1.000,5"), nil, "gemischte Trennzeichen")
	eq(Staff.ParseAmount("1000t"), 1e15, "Obergrenze 1e15")
	eq(Staff.ParseAmount("1001t"), nil, "über 1e15")
	eq(Staff.ParseAmount(nil), nil, "nil")
	eq(Staff.ParseAmount(1234.9), 1234, "Zahl")
	eq(Staff.ParseAmount(0 / 0), nil, "NaN")
	eq(Staff.ParseAmount(math.huge), nil, "inf")
end)

-- ---------------------------------------------------------------------
-- 3) ParseCommand / IsCommandText / Tokenize
-- ---------------------------------------------------------------------
check("3 ParseCommand/IsCommandText", function()
	local def, args, prefix, name = Staff.ParseCommand("/kick Bob spam")
	eq(def and def.Name, "kick", "def")
	eq(#args, 2, "#args")
	eq(args[1], "Bob", "args[1]")
	eq(args[2], "spam", "args[2]")
	eq(prefix, "/", "prefix")
	eq(name, "kick", "name")
	def, args, prefix = Staff.ParseCommand(";KICK  bob")
	eq(def and def.Name, "kick", ";KICK")
	eq(prefix, ";", "prefix ;")
	eq(args[1], "bob", "args ;")
	eq((Staff.ParseCommand("/goto x")) and (Staff.ParseCommand("/goto x")).Name, "tp", "/goto -> tp")
	eq((Staff.ParseCommand(";)")), nil, ";)")
	eq((Staff.ParseCommand("hello")), nil, "hello")
	eq((Staff.ParseCommand("kick bob")), nil, "ohne Präfix nie ein Befehl")
	eq((Staff.ParseCommand("/ kick bob")), nil, "Leerzeichen hinter dem Präfix")
	eq((Staff.ParseCommand(nil)), nil, "nil")
	local long = "/warn bob " .. string.rep("x", 400)
	local ok, longDef, longArgs = pcall(Staff.ParseCommand, long)
	truthy(ok, "400 Byte ohne Fehler")
	eq(longDef and longDef.Name, "warn", "lang: def")
	eq(#longArgs[2], 100, "lang: Wort auf 100 Byte gekürzt")
	truthy(Staff.IsCommandText(";kick bob", ";"), ";kick bob")
	truthy(Staff.IsCommandText(";KICK", ";"), ";KICK")
	falsy(Staff.IsCommandText(";)", ";"), ";)")
	falsy(Staff.IsCommandText(";hallo du", ";"), ";hallo (kein Befehl)")
	falsy(Staff.IsCommandText(";kickbob", ";"), ";kickbob")
	falsy(Staff.IsCommandText("/kick", ";"), "/kick mit ;-Präfix")
	truthy(Staff.IsCommandText("/kick"), "/kick ohne Präfix-Vorgabe")
	falsy(Staff.IsCommandText("hello"), "hello")
	falsy(Staff.IsCommandText(nil), "nil")
	local tokens = Staff.Tokenize(string.rep("a ", 60))
	eq(#tokens, 40, "höchstens 40 Wörter")
	eq(#Staff.Tokenize(nil :: any), 0, "Tokenize(nil)")
end)

-- ---------------------------------------------------------------------
-- 4) MatchTargets
-- ---------------------------------------------------------------------
local A = { Name = "RizzG315", DisplayName = "Rizz", UserId = 1 }
local B = { Name = "Bob123", DisplayName = "Bobby", UserId = 2 }
local C = { Name = "Bobcat", DisplayName = "Kat", UserId = 3 }
local D = { Name = "Lea", DisplayName = "Bobby", UserId = 4 }
local PLAYERS = { A, B, C, D }

check("4 MatchTargets", function()
	local list, key, arg = Staff.MatchTargets("me", PLAYERS, A)
	eq(names(list), "RizzG315", "me")
	eq(key, nil, "me ohne Fehler")
	eq(#Staff.MatchTargets("all", PLAYERS, A), 4, "all")
	eq(#Staff.MatchTargets("ALL", PLAYERS, A), 4, "ALL")
	eq(names(Staff.MatchTargets("others", PLAYERS, A)), "Bob123,Bobcat,Lea", "others")
	eq(names(Staff.MatchTargets("2", PLAYERS, A)), "Bob123", "UserId 2")
	eq(names(Staff.MatchTargets(2, PLAYERS, A)), "Bob123", "UserId als Zahl")
	eq(names(Staff.MatchTargets("@kat", PLAYERS, A)), "Bobcat", "@kat")
	list, key, arg = Staff.MatchTargets("@bobby", PLAYERS, A)
	eq(#list, 0, "@bobby leer")
	eq(key, "admin.cmd.ambiguous", "@bobby mehrdeutig")
	truthy(arg and string.find(arg, "@bobby|", 1, true) == 1, "errArg Text|Namen")
	truthy(arg and string.find(arg, "Bob123", 1, true) and string.find(arg, "Lea", 1, true), "errArg nennt beide")
	list, key = Staff.MatchTargets("bob", PLAYERS, A)
	eq(#list, 0, "bob leer")
	eq(key, "admin.cmd.ambiguous", "bob mehrdeutig (Bob123/Bobcat)")
	eq(names(Staff.MatchTargets("bob1", PLAYERS, A)), "Bob123", "bob1")
	eq(names(Staff.MatchTargets("riz", PLAYERS, A)), "RizzG315", "riz")
	eq(names(Staff.MatchTargets("BOBCAT", PLAYERS, A)), "Bobcat", "Name exakt (groß/klein egal)")
	eq(names(Staff.MatchTargets("kat", PLAYERS, A)), "Bobcat", "Anzeigename exakt")
	list, key, arg = Staff.MatchTargets("x", PLAYERS, A)
	eq(#list, 0, "x leer")
	eq(key, "admin.cmd.noTarget", "x noTarget")
	eq(arg, "x", "x errArg")
	eq(names(Staff.MatchTargets("lea,bobcat", PLAYERS, A)), "Lea,Bobcat", "Liste")
	eq(names(Staff.MatchTargets("lea, bobcat, lea", PLAYERS, A)), "Lea,Bobcat", "Liste ohne Doppelte")
	list, key, arg = Staff.MatchTargets("lea,zzz", PLAYERS, A)
	eq(#list, 0, "lea,zzz leer")
	eq(key, "admin.cmd.noTarget", "lea,zzz noTarget")
	eq(arg, "zzz", "lea,zzz errArg")
	list, key = Staff.MatchTargets("lea,all", PLAYERS, A)
	eq(#list, 0, "all in Liste gesperrt")
	eq(key, "admin.cmd.noTarget", "all in Liste")
	list = Staff.MatchTargets("1,2,3,4,1,2,3,4,1,2,3", PLAYERS, A)
	eq(#list, 0, "mehr als 10 Teile")
	list, key = Staff.MatchTargets("99", PLAYERS, A)
	eq(key, "admin.cmd.noTarget", "Ziffern nur als UserId")
	eq(names(Staff.MatchTargets(nil, PLAYERS, A)), "RizzG315", "nil = me")
	eq(names(Staff.MatchTargets("", PLAYERS, A)), "RizzG315", "leer = me")
	list, key = Staff.MatchTargets("me", PLAYERS, nil)
	eq(key, "admin.cmd.noTarget", "me ohne Handelnden")
	truthy(
		Staff.IsMass("all") and Staff.IsMass(" Others ") and not Staff.IsMass("lea") and not Staff.IsMass(nil),
		"IsMass"
	)
end)

-- ---------------------------------------------------------------------
-- 5) Can-Matrix
-- ---------------------------------------------------------------------
check("5 Can-Matrix", function()
	local cfg = defaultCfg()
	truthy(Staff.Can("Moderator", "Kick", cfg), "Mod Kick")
	truthy(Staff.Can("Moderator", "TempBan", cfg), "Mod TempBan")
	truthy(Staff.Can("Moderator", "UnbanOwn", cfg), "Mod UnbanOwn")
	truthy(Staff.Can("Moderator", "BanView", cfg), "Mod BanView")
	falsy(Staff.Can("Moderator", "Ban", cfg), "Mod Ban")
	falsy(Staff.Can("Moderator", "Unban", cfg), "Mod Unban")
	falsy(Staff.Can("Moderator", "MarketEvents", cfg), "Mod MarketEvents")
	truthy(Staff.Can("Admin", "Ban", cfg), "Admin Ban")
	truthy(Staff.Can("Admin", "GiveCredits", cfg), "Admin GiveCredits")
	falsy(Staff.Can("Admin", "GiveAky", cfg), "Admin GiveAky")
	truthy(Staff.Can("Admin", "ManageMods", cfg), "Admin ManageMods")
	falsy(Staff.Can("Admin", "ManageAdmins", cfg), "Admin ManageAdmins")
	local noMods = defaultCfg()
	noMods.AdminCanManageMods = false
	falsy(Staff.Can("Admin", "ManageMods", noMods), "Admin ManageMods ohne AdminCanManageMods")
	truthy(Staff.Can("Owner", "ManageMods", noMods), "Owner ManageMods immer")
	for _, perm in ipairs(Staff.PERMS) do
		truthy(Staff.Can("Owner", perm, cfg), "Owner " .. perm)
		falsy(Staff.Can(nil, perm, cfg), "nil " .. perm)
		falsy(Staff.Can("Boss", perm, cfg), "unbekannte Rolle " .. perm)
	end
	falsy(Staff.Can("Owner", "Gibtsnicht", cfg), "unbekanntes Recht")
	local hacked = defaultCfg()
	for perm in pairs(Staff.LOCKED_OWNER) do
		hacked.Perms[perm] = "Moderator"
	end
	for perm in pairs(Staff.LOCKED_OWNER) do
		falsy(Staff.Can("Moderator", perm, hacked), "gesperrt " .. perm .. " (Mod)")
		falsy(Staff.Can("Admin", perm, hacked), "gesperrt " .. perm .. " (Admin)")
		truthy(Staff.Can("Owner", perm, hacked), "gesperrt " .. perm .. " (Owner)")
	end
	falsy(Staff.Can("Admin", "Ban", nil), "ohne cfg nur Owner")
	truthy(Staff.Can("Owner", "Ban", nil), "Owner ohne cfg")
	truthy(Staff.CanAny("Moderator", { "Ban", "Kick" }, cfg), "CanAny")
	falsy(Staff.CanAny("Moderator", { "Ban", "Debug" }, cfg), "CanAny falsch")
	eq(Staff.Rank("Owner"), 3, "Rank Owner")
	eq(Staff.Rank("Admin"), 2, "Rank Admin")
	eq(Staff.Rank("Moderator"), 1, "Rank Mod")
	eq(Staff.Rank(nil), 0, "Rank nil")
	eq(Staff.Rank("Boss"), 0, "Rank unbekannt")
end)

-- ---------------------------------------------------------------------
-- 6) CanActOn
-- ---------------------------------------------------------------------
check("6 CanActOn", function()
	truthy(Staff.CanActOn(3, 2), "(3,2)")
	falsy(Staff.CanActOn(2, 2), "(2,2)")
	truthy(Staff.CanActOn(1, 0), "(1,0)")
	falsy(Staff.CanActOn(1, 2), "(1,2)")
	falsy(Staff.CanActOn(3, 3), "Owner vs Owner geschützt")
	falsy(Staff.CanActOn(0 / 0, 0), "NaN")
end)

-- ---------------------------------------------------------------------
-- 7) CanSetRole
-- ---------------------------------------------------------------------
check("7 CanSetRole", function()
	local cfg = defaultCfg()
	local ok, err = Staff.CanSetRole("Owner", 0, false, "Admin", cfg)
	truthy(ok, "Owner -> Admin auf Rang 0")
	ok = Staff.CanSetRole("Owner", 2, false, "Moderator", cfg)
	truthy(ok, "Owner stuft Admin zu Moderator herab")
	ok, err = Staff.CanSetRole("Admin", 0, false, "Admin", cfg)
	falsy(ok, "Admin -> Admin")
	eq(err, "admin.role.cantGrant", "Admin -> Admin Fehler")
	ok = Staff.CanSetRole("Admin", 0, false, "Moderator", cfg)
	truthy(ok, "Admin -> Moderator auf Rang 0")
	ok = Staff.CanSetRole("Admin", 1, false, nil, cfg)
	truthy(ok, "Admin entfernt Moderator")
	ok = Staff.CanSetRole("Admin", 1, false, "", cfg)
	truthy(ok, "Admin entfernt Moderator ('' = entfernen)")
	ok, err = Staff.CanSetRole("Admin", 2, false, nil, cfg)
	falsy(ok, "Admin entfernt Admin")
	eq(err, "admin.role.cantRemove", "Admin entfernt Admin Fehler")
	ok, err = Staff.CanSetRole("Admin", 2, false, "Moderator", cfg)
	falsy(ok, "Admin stuft Admin herab")
	eq(err, "admin.role.cantRemove", "Admin stuft Admin herab Fehler")
	ok, err = Staff.CanSetRole("Moderator", 0, false, "Moderator", cfg)
	falsy(ok, "Moderator -> Moderator")
	eq(err, "admin.role.cantGrant", "Moderator -> Moderator Fehler")
	ok, err = Staff.CanSetRole("Moderator", 0, false, nil, cfg)
	falsy(ok, "Moderator entfernt")
	eq(err, "admin.role.cantRemove", "Moderator entfernt Fehler")
	for _, actor in ipairs({ "Owner", "Admin", "Moderator" }) do
		ok, err = Staff.CanSetRole(actor, 3, true, "Moderator", cfg)
		falsy(ok, actor .. " -> Besitzer")
		eq(err, "admin.role.owner", actor .. " -> Besitzer Fehler")
	end
	ok, err = Staff.CanSetRole("Owner", 0, false, "Owner", cfg)
	falsy(ok, "Rolle Owner vergeben")
	eq(err, "admin.role.badRole", "badRole")
	ok, err = Staff.CanSetRole(nil, 0, false, "Moderator", cfg)
	eq(err, "admin.role.cantGrant", "Spieler vergibt")
	local noMods = defaultCfg()
	noMods.AdminCanManageMods = false
	ok, err = Staff.CanSetRole("Admin", 0, false, "Moderator", noMods)
	eq(err, "admin.role.cantGrant", "ohne AdminCanManageMods")
	ok, err = Staff.CanSetRole("Owner", 0 / 0, false, "Moderator", cfg)
	eq(err, "admin.role.owner", "unbekannter Rang = geschützt")
end)

-- ---------------------------------------------------------------------
-- 8) ResolveRole
-- ---------------------------------------------------------------------
check("8 ResolveRole", function()
	local group = { Id = 5, AdminRank = 254, ModeratorRank = 200 }
	eq(Staff.ResolveRole({ IsOwner = true, Stored = "Moderator", Group = group }), "Owner", "Besitzer gewinnt")
	eq(
		Staff.ResolveRole({ IsOwner = false, Stored = "Admin", GroupRank = 200, Group = group }),
		"Admin",
		"Admin + Gruppe 200"
	)
	eq(Staff.ResolveRole({ IsOwner = false, GroupRank = 254, Group = group }), "Admin", "Rang 254")
	eq(Staff.ResolveRole({ IsOwner = false, GroupRank = 255, Group = group }), "Admin", "Rang 255")
	eq(Staff.ResolveRole({ IsOwner = false, GroupRank = 200, Group = group }), "Moderator", "Rang 200")
	eq(Staff.ResolveRole({ IsOwner = false, Stored = "Moderator", GroupRank = 254, Group = group }), "Admin", "max")
	eq(Staff.ResolveRole({ IsOwner = false, GroupRank = 100, Group = group }), nil, "Rang 100")
	local off = { Id = 0, AdminRank = 254, ModeratorRank = 200 }
	eq(Staff.ResolveRole({ IsOwner = false, GroupRank = 255, Group = off }), nil, "Group.Id 0 ignoriert Rang")
	eq(
		Staff.ResolveRole({ IsOwner = false, Stored = "Moderator", GroupRank = 255, Group = off }),
		"Moderator",
		"gespeichert"
	)
	eq(Staff.ResolveRole({ IsOwner = false, Stored = "Owner" }), nil, "Owner nie gespeichert")
	eq(
		Staff.ResolveRole({ IsOwner = false, GroupRank = 0, Group = { Id = 5, AdminRank = 254, ModeratorRank = 0 } }),
		nil,
		"Gast nie Mod"
	)
	eq(Staff.ResolveRole(nil), nil, "nil")
end)

-- ---------------------------------------------------------------------
-- 9) ShouldDeliver
-- ---------------------------------------------------------------------
check("9 ShouldDeliver", function()
	local now = 1000
	local muted = { [10] = 2000, [11] = -1, [12] = 500 }
	local personal = { [20] = { [13] = true } }
	local function deliver(text: string?, sender: number?, recipient: number): boolean
		return Staff.ShouldDeliver({
			Text = text,
			SenderId = sender,
			RecipientId = recipient,
			MutedUntil = muted,
			Personal = personal,
			Now = now,
		})
	end
	truthy(deliver("hallo", nil, 20), "System")
	falsy(deliver("hallo", 10, 20), "stumm bis später")
	falsy(deliver("hallo", 11, 20), "stumm dauerhaft")
	truthy(deliver("hallo", 12, 20), "abgelaufen")
	falsy(deliver(";kick x", 14, 20), ";kick x an andere")
	truthy(deliver(";kick x", 14, 14), ";kick x an sich selbst")
	truthy(deliver(";)", 14, 20), ";)")
	falsy(deliver("hallo", 13, 20), "persönlich stumm für 20")
	truthy(deliver("hallo", 13, 21), "nicht stumm für 21")
	truthy(Staff.ShouldDeliver(nil), "kaputte Info -> zustellen")
end)

-- ---------------------------------------------------------------------
-- 10) ValidateMsg
-- ---------------------------------------------------------------------
check("10 ValidateMsg", function()
	local now = 1800000000
	local role =
		Staff.ValidateMsg({ Kind = "Role", Id = "abcd1234", UserId = 55, Role = "Admin", Rev = 3, By = 7, X = 1 }, now)
	truthy(role, "Role gültig")
	eq(role and role.X, nil, "nur bekannte Felder")
	eq(role and role.Role, "Admin", "Role.Role")
	truthy(
		Staff.ValidateMsg({ Kind = "Role", Id = "abcd", UserId = 55, Role = "", Rev = 0, By = 7 }, now),
		"Role entfernen"
	)
	local kick = Staff.ValidateMsg({ Kind = "Kick", Id = "k-0001", UserId = 9, Reason = "Regeln", Until = -1 }, now)
	truthy(kick and kick.Until == -1, "Kick dauerhaft")
	truthy(
		Staff.ValidateMsg({ Kind = "Kick", Id = "k-0002", UserId = 9, Reason = "", Until = now + 3600 }, now),
		"Kick Zeit"
	)
	local report =
		Staff.ValidateMsg({ Kind = "Report", Id = "r-0001", FromName = "Ann", TargetName = "Bob", Reason = "Fly" }, now)
	truthy(report and report.Reason == "Fly", "Report gültig")
	eq(Staff.ValidateMsg({ Kind = "Boom", Id = "abcd1234" }, now), nil, "falsche Art")
	eq(
		Staff.ValidateMsg({ Kind = "Role", Id = "abc", UserId = 55, Role = "Admin", Rev = 3, By = 7 }, now),
		nil,
		"Id zu kurz"
	)
	eq(
		Staff.ValidateMsg({ Kind = "Role", Id = "abcd1234", UserId = 55, Role = "Owner", Rev = 3, By = 7 }, now),
		nil,
		"Owner"
	)
	eq(
		Staff.ValidateMsg({ Kind = "Role", Id = "abcd1234", UserId = 1.5, Role = "Admin", Rev = 3, By = 7 }, now),
		nil,
		"UserId 1.5"
	)
	eq(
		Staff.ValidateMsg({ Kind = "Role", Id = "abcd1234", UserId = -1, Role = "Admin", Rev = 3, By = 7 }, now),
		nil,
		"UserId ≤ 0"
	)
	eq(
		Staff.ValidateMsg({ Kind = "Kick", Id = "k-0003", UserId = 9, Reason = string.rep("x", 500), Until = -1 }, now),
		nil,
		"Reason 500 Byte"
	)
	eq(
		Staff.ValidateMsg(
			{ Kind = "Kick", Id = "k-0004", UserId = 9, Reason = "x", Until = now + 20 * 365 * 86400 },
			now
		),
		nil,
		"Until > 10 Jahre"
	)
	eq(
		Staff.ValidateMsg({ Kind = "Report", Id = "r-0002", FromName = "Ann", TargetName = "Bob", Reason = "Xyz" }, now),
		nil,
		"Report Reason Xyz"
	)
	eq(
		Staff.ValidateMsg(
			{ Kind = "Report", Id = "r-0003", FromName = string.rep("a", 21), TargetName = "Bob", Reason = "Fly" },
			now
		),
		nil,
		"FromName > 20"
	)
	eq(Staff.ValidateMsg("kaputt", now), nil, "kein Tisch")
end)

-- ---------------------------------------------------------------------
-- 11) COMMANDS / EVENTS Integrität
-- ---------------------------------------------------------------------
check("11 COMMANDS/EVENTS", function()
	eq(#Staff.COMMANDS, 31, "31 Befehle")
	local permSet = {}
	for _, perm in ipairs(Staff.PERMS) do
		permSet[perm] = true
	end
	local seen = {}
	for _, def in ipairs(Staff.COMMANDS) do
		for _, name in ipairs({ def.Name, def.Alias or def.Name }) do
			truthy(string.match(name, "^%l+$") and #name <= 12, "Kleinbuchstaben " .. name)
			falsy(Staff.RESERVED[name], "reserviert " .. name)
		end
		falsy(seen[def.Name], "doppelt " .. def.Name)
		seen[def.Name] = true
		if def.Alias then
			falsy(seen[def.Alias], "doppelt " .. def.Alias)
			seen[def.Alias] = true
		end
		truthy(def.Perm == "" or permSet[def.Perm], "Perm " .. def.Name)
		for _, perm in ipairs(def.AnyPerm or {}) do
			truthy(permSet[perm], "AnyPerm " .. def.Name .. " " .. perm)
		end
		eq(Staff.CommandByName(def.Name), def, "CommandByName " .. def.Name)
		if def.Alias then
			eq(Staff.CommandByName(def.Alias), def, "CommandByName Alias " .. def.Alias)
		end
	end
	eq(Staff.CommandByName("unban").Perm, "UnbanOwn", "unban.Perm")
	truthy(Staff.CommandByName("shutdown").Confirm, "shutdown.Confirm")
	truthy(Staff.RESERVED.trade and Staff.RESERVED.terminal, "trade/terminal reserviert")
	truthy(permSet.UnbanOwn and permSet.BanView, "PERMS enthält UnbanOwn/BanView")
	eq(#Staff.PERMS, 46, "46 Rechte")
	local locked = 0
	for perm in pairs(Staff.LOCKED_OWNER) do
		truthy(permSet[perm], "LOCKED bekannt " .. perm)
		locked += 1
	end
	eq(locked, 8, "8 gesperrte Besitzer-Rechte")
	falsy(
		Staff.LOCKED_OWNER.UnbanOwn or Staff.LOCKED_OWNER.BanView or Staff.LOCKED_OWNER.Unban,
		"W26-Rechte nicht gesperrt"
	)
	for name, value in pairs(Staff.EVENTS) do
		local spec, key = Staff.EventSpec(name)
		truthy(type(spec) == "table" and spec.Type, "EVENTS " .. name)
		if type(value) == "string" then
			eq(key, value, "Alias " .. name)
			eq(type(Staff.EVENTS[value]), "table", "Alias zeigt auf Tabelle " .. name)
		end
	end
	local golden = Staff.EventSpec("GoldenHour")
	eq(golden and golden.Kind, "GoldenHour", "EventSpec Alias groß/klein")
	eq((Staff.EventSpec("gibtsnicht")), nil, "EventSpec unbekannt")
	truthy(
		table.find(Staff.EventNames(), "rain") and not table.find(Staff.EventNames(), "moneyrain"),
		"EventNames ohne Aliase"
	)
	local cfg = defaultCfg()
	truthy(Staff.VisibleCommand(Staff.CommandByName("cmds"), nil, cfg), "cmds für alle")
	truthy(Staff.VisibleCommand(Staff.CommandByName("mute"), nil, cfg), "mute persönlich für alle")
	truthy(Staff.VisibleCommand(Staff.CommandByName("unban"), "Moderator", cfg), "unban für Mod")
	falsy(Staff.VisibleCommand(Staff.CommandByName("fly"), "Moderator", cfg), "fly nicht für Mod")
	truthy(Staff.VisibleCommand(Staff.CommandByName("event"), "Admin", cfg), "event für Admin")
	falsy(Staff.VisibleCommand(Staff.CommandByName("event"), "Moderator", cfg), "event nicht für Mod")
	truthy(Staff.VisibleCommand(Staff.CommandByName("shutdown"), "Owner", cfg), "shutdown für Owner")
	falsy(Staff.VisibleCommand(Staff.CommandByName("shutdown"), "Admin", cfg), "shutdown nicht für Admin")
	local worldOnly = defaultCfg()
	worldOnly.Perms.FunEvents = "Owner"
	truthy(Staff.VisibleCommand(Staff.CommandByName("event"), "Admin", worldOnly), "event über AnyPerm (WorldEvents)")
end)

-- ---------------------------------------------------------------------
-- 12) ReasonFromText
-- ---------------------------------------------------------------------
check("12 ReasonFromText", function()
	eq(Staff.ReasonFromText("hack"), "Exploit", "hack")
	eq(Staff.ReasonFromText("Beleidigung"), "Toxic", "Beleidigung")
	eq(Staff.ReasonFromText("fliegen"), "Fly", "fliegen")
	eq(Staff.ReasonFromText("tempo"), "Speed", "tempo")
	eq(Staff.ReasonFromText("egal"), "Other", "egal")
	eq(Staff.ReasonFromText(nil), "Other", "nil")
	for _, word in ipairs({ "hack", "Beleidigung", "fliegen", "tempo", "egal" }) do
		truthy(table.find(Staff.REPORT_REASONS, Staff.ReasonFromText(word)), "in REPORT_REASONS " .. word)
	end
end)

-- ---------------------------------------------------------------------
-- 13) CheckPerms
-- ---------------------------------------------------------------------
check("13 CheckPerms", function()
	local cfg = defaultCfg()
	eq(#Staff.CheckPerms(cfg.Perms, cfg.EventPerms), 0, "Standard ohne Fehler")
	local missing = defaultCfg()
	missing.Perms.Kick = nil
	truthy(contains(Staff.CheckPerms(missing.Perms, missing.EventPerms), "Perms.Kick"), "Kick fehlt")
	local locked = defaultCfg()
	locked.Perms.Debug = "Admin"
	truthy(contains(Staff.CheckPerms(locked.Perms, locked.EventPerms), "Perms.Debug"), "Debug gesperrt")
	local unknown = defaultCfg()
	unknown.Perms.Zaubern = "Admin"
	truthy(contains(Staff.CheckPerms(unknown.Perms, unknown.EventPerms), "Perms.Zaubern"), "unbekanntes Recht")
	local badRole = defaultCfg()
	badRole.Perms.Kick = "Chef"
	truthy(contains(Staff.CheckPerms(badRole.Perms, badRole.EventPerms), "Perms.Kick"), "falsche Rolle")
	local badEvent = defaultCfg()
	badEvent.EventPerms.Truck = "Fahren"
	truthy(contains(Staff.CheckPerms(badEvent.Perms, badEvent.EventPerms), "EventPerms.Truck"), "Event-Recht unbekannt")
	truthy(#Staff.CheckPerms(nil, nil) >= 2, "keine Tabellen")
end)

-- ---------------------------------------------------------------------
-- 14) CanUnban (W26)
-- ---------------------------------------------------------------------
check("14 CanUnban", function()
	local cfg = defaultCfg()
	local foreignPerm = { By = 99, Until = -1 }
	local ownTemp = { By = 7, Until = 1900000000 }
	local ownPerm = { By = 7, Until = -1 }
	local foreignTemp = { By = 99, Until = 1900000000 }
	local ok, err = Staff.CanUnban("Admin", 7, foreignPerm, cfg)
	truthy(ok, "Admin fremd/dauerhaft")
	ok = Staff.CanUnban("Admin", 7, nil, cfg)
	truthy(ok, "Admin ohne Eintrag")
	ok = Staff.CanUnban("Owner", 1, foreignPerm, cfg)
	truthy(ok, "Owner")
	ok, err = Staff.CanUnban("Moderator", 7, ownTemp, cfg)
	truthy(ok, "Mod eigener Zeit-Bann")
	eq(err, nil, "Mod eigener Zeit-Bann ohne Fehler")
	ok, err = Staff.CanUnban("Moderator", 7, ownPerm, cfg)
	falsy(ok, "Mod eigener Dauer-Bann")
	eq(err, "admin.bans.modOwnOnly", "Mod eigener Dauer-Bann Fehler")
	ok, err = Staff.CanUnban("Moderator", 7, foreignTemp, cfg)
	falsy(ok, "Mod fremd")
	eq(err, "admin.bans.modOwnOnly", "Mod fremd Fehler")
	ok, err = Staff.CanUnban("Moderator", 7, nil, cfg)
	falsy(ok, "Mod ohne Eintrag")
	eq(err, "admin.bans.modOwnOnly", "Mod ohne Eintrag Fehler")
	ok, err = Staff.CanUnban("Moderator", 7, { By = 7 }, cfg)
	falsy(ok, "Mod Eintrag ohne Until")
	ok, err = Staff.CanUnban(nil, 7, ownTemp, cfg)
	falsy(ok, "nil-Rolle")
	eq(err, "admin.cmd.denied", "nil-Rolle Fehler")
end)

-- ---------------------------------------------------------------------
-- 15) CanUndo (§16.2 Nr. 5)
-- ---------------------------------------------------------------------
check("15 CanUndo", function()
	truthy(Staff.CanUndo(3, 3, true, true), "Owner sich selbst")
	falsy(Staff.CanUndo(1, 1, true, false), "Mod sich selbst")
	falsy(Staff.CanUndo(2, 1, true, false), "Admin sich selbst")
	truthy(Staff.CanUndo(1, 1, false, false), "Mod hebt Mod-Strafe auf")
	falsy(Staff.CanUndo(1, 2, false, false), "Mod hebt Admin-Strafe nicht auf")
	truthy(Staff.CanUndo(2, 1, false, false), "Admin hebt Mod-Strafe auf")
	falsy(Staff.CanUndo(2, 3, false, false), "Admin hebt Owner-Strafe nicht auf")
	truthy(Staff.CanUndo(3, 3, false, true), "Owner hebt Owner-Strafe auf")
	truthy(Staff.CanUndo(1, nil :: any, false, false), "unbekannter Bestrafender = 0")
	truthy(Staff.CanUndo(1, 0, false, false), "Anti-Cheat (0)")
end)

-- ---------------------------------------------------------------------
-- 16) Config.Security.Staff (echte Werte) + Validate mit Staff
-- ---------------------------------------------------------------------
check("16 Config.Security.Staff", function()
	local staff = Security.Staff
	truthy(type(staff) == "table", "Security.Staff")
	eq(#Staff.CheckPerms(staff.Perms, staff.EventPerms), 0, "echte Perms/EventPerms ohne Fehler")
	for perm in pairs(Staff.LOCKED_OWNER) do
		eq(staff.Perms[perm], "Owner", "gesperrt in Config " .. perm)
	end
	eq(staff.Perms.UnbanOwn, "Moderator", "UnbanOwn")
	eq(staff.Perms.BanView, "Moderator", "BanView")
	for _, key in ipairs({ "HeavyGap", "AnnounceGap", "FunEventGap", "BanIndexMax", "BanPageSize", "UnbanReasonMax" }) do
		truthy(type(staff[key]) == "number" and staff[key] > 0, "Schlüssel " .. key)
	end
	truthy(type(staff.LookupLimit) == "table" and type(staff.BanReconcile) == "table", "LookupLimit/BanReconcile")
	eq(Security.Rates.Command[1], 6, "Rates.Command")
	eq(Security.Rates.Role[2], 60, "Rates.Role")
	local errors = Security.Validate({}, Staff)
	eq(#errors, 0, "Validate ohne Fehler: " .. table.concat(errors, " | "))
	-- gesperrte Rechte niedriger gesetzt -> Validate meldet sie
	local saved = deepCopy(staff)
	local ok, err = pcall(function()
		for perm in pairs(Staff.LOCKED_OWNER) do
			staff.Perms[perm] = "Admin"
		end
		staff.Group.ModeratorRank = 0
		staff.DefaultBan = "bald"
		staff.BanPageSize = 0
		local bad = Security.Validate({}, Staff)
		for perm in pairs(Staff.LOCKED_OWNER) do
			truthy(contains(bad, "Config.Security.Staff.Perms." .. perm), "Validate meldet " .. perm)
		end
		truthy(contains(bad, "Staff.Group"), "Validate meldet Gruppe")
		truthy(contains(bad, "Staff.DefaultBan"), "Validate meldet DefaultBan")
		truthy(contains(bad, "Staff.BanPageSize"), "Validate meldet BanPageSize")
	end)
	Security.Staff = saved
	if not ok then
		error(err, 0)
	end
	eq(#Security.Validate({}, Staff), 0, "wiederhergestellt")
end)

-- ---------------------------------------------------------------------
-- 17) Lang/Team: DE/EN vollständig, Befehls-Texte, keine Doppelten mit Lang/Admin
-- ---------------------------------------------------------------------
check("17 Lang/Team", function()
	local function placeholders(text: string): number
		local count = 0
		for token in string.gmatch(text, "%%[%-+#0]*%d*%.?%d*[sdifqxXc%%]") do
			if token ~= "%%" then
				count += 1
			end
		end
		return count
	end
	for _, lang in ipairs({ "de", "en" }) do
		local other = if lang == "de" then "en" else "de"
		for key, text in pairs(LangTeam[lang]) do
			truthy(string.sub(key, 1, 6) == "admin.", "Präfix " .. key)
			truthy(type(text) == "string" and text ~= "", "Text " .. lang .. " " .. key)
			truthy(LangTeam[other][key], key .. " fehlt in " .. other)
			eq(placeholders(text), placeholders(LangTeam[other][key] or ""), "Platzhalter " .. key)
			falsy(LangAdmin.de[key] or LangAdmin.en[key], "doppelt mit Lang/Admin " .. key)
		end
	end
	for _, def in ipairs(Staff.COMMANDS) do
		for _, kind in ipairs({ "u", "h" }) do
			local key = ("admin.cmd.%s.%s"):format(kind, def.Name)
			truthy(LangTeam.de[key] and LangTeam.en[key], "Befehls-Text " .. key)
		end
	end
	for _, key in ipairs({
		"admin.tabBans",
		"admin.bans.modOwnOnly",
		"admin.bans.done",
		"admin.bans.state.Active",
		"admin.bans.state.Unbanned",
		"admin.bans.state.Expired",
		"admin.bans.state.Unknown",
		"admin.ownerUnknown",
		"admin.cmd.rankUnknown",
		"admin.cmd.noSelfGive",
		"admin.cmd.eventGap",
	}) do
		truthy(LangTeam.de[key] and LangTeam.en[key], "§16-Schlüssel " .. key)
	end
	for _, role in ipairs(Staff.ROLES) do
		for _, prefix in ipairs({ "admin.role.", "admin.role.chip.", "admin.tag." }) do
			truthy(LangTeam.de[prefix .. role] and LangTeam.en[prefix .. role], "Rollen-Text " .. prefix .. role)
		end
	end
	eq(LangTeam.de["admin.cmd.u.unban"], "/unban <Name|UserId> [Grund]", "unban-Nutzung (§16.1)")
	eq(LangAdmin.de["admin.notOwner"], "Gleicher oder höherer Rang ist geschützt", "Admin.notOwner (§10.2)")
	eq(LangAdmin.en["admin.targetHint"], "Target: name, @displayname, UserId, me, all or others", "Admin.targetHint")
end)

-- ---------------------------------------------------------------------
print(("[staff.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	for _, failure in ipairs(failures) do
		print("  FAIL " .. failure)
	end
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
