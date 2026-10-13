-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Kern (Server/Tests/CoreTests)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C17 + §D WP1 "Tests" (SelfTestService lädt dieses Modul).
--  Gibt { [testName]: (Services) -> () } zurück; jeder Fehler = FAIL.
--  Prüft: Config.Validate leer, Config.ApplyLive (nur LiveFields, geklemmt, Codes nur CR/Kosmetik, Rücksetzen),
--  Lang.Missing leer + Pflicht-Schlüssel, DEFAULT_DATA (String-Schlüssel, JSON, Sanitize/Migrate, Ringpuffer),
--  Scheduler-Statistik, Net-Liste vollständig = ReplicatedStorage.Remotes, AssetSlot mit 0 -> Rezept,
--  Util/Spring/Format/Clock (Sommerzeit-Grenzen), Types ladbar.
-- =====================================================================

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Spring = require(Shared:WaitForChild("Spring"))
local Lang = require(Shared:WaitForChild("Lang"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Clock = require(Shared:WaitForChild("Clock"))
local AssetSlot = require(Shared:WaitForChild("AssetSlot"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function listText(list: { string }): string
	local shown = {}
	for i = 1, math.min(#list, 8) do
		shown[i] = list[i]
	end
	return table.concat(shown, " | ") .. (if #list > 8 then (" … (+%d)"):format(#list - 8) else "")
end

local function dataServiceOf(services: any): any
	local dataService = services and services.DataService
	if dataService then
		return dataService
	end
	local folder = script.Parent.Parent:FindFirstChild("Services")
	local module = folder and folder:FindFirstChild("DataService")
	assert(module and module:IsA("ModuleScript"), "DataService fehlt")
	return require(module) :: any
end

local Tests = {}

-- ---------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------
Tests["Config.Validate leer"] = function()
	local errors = Config.Validate()
	assert(#errors == 0, ("%d Problem(e): %s"):format(#errors, listText(errors)))
end

Tests["Config Kern-Werte"] = function()
	eq(Config.GameName, "AKYTEX TYCOON")
	eq(Config.Server.MaxMoney, 9e15, "MaxMoney")
	assert(Config.Server.MaxMoney < 2 ^ 53, "MaxMoney < 2^53")
	eq(Config.Tech.DataStoreName, "AT_Player_v1")
	eq(Config.Tech.KeyPrefix, "P_")
	eq(Config.Admin.StudioAllPlayersAdmin, false, "Player2 nie Admin")
	assert(Config.Tech.StateFlush >= 0.2, "State höchstens 5×/s")
	eq(Config.Tech.FullStateEvery, 20)
	assert(typeof(Config.Colors.Accent) == "Color3", "Colors.Accent")
	for _, key in ipairs({ "T", "E", "M", "K", "G", "F" }) do
		assert(typeof(Config.Colors.Sectors[key]) == "Color3", "Sektorfarbe " .. key)
	end
	for _, name in ipairs({
		"Security",
		"Client",
		"Quality",
		"Market",
		"Companies",
		"News",
		"Trading",
		"Tower",
		"City",
		"Vehicles",
		"Decor",
		"Lifestyle",
		"Progression",
		"Season",
		"Rewards",
		"Shop",
		"Events",
	}) do
		assert(
			type((Config :: any)[name]) == "table",
			"Config." .. name .. " fehlt (auch leer muss eine Tabelle da sein)"
		)
	end
end

Tests["Config.ApplyLive klemmt, filtert, setzt zurück"] = function()
	local market: any = Config.Market
	local before = market.NewsMeanGap
	local maxMoney = Config.Server.MaxMoney
	local ok, err = pcall(function()
		local applied, issues = Config.ApplyLive({
			["Market.NewsMeanGap"] = 1e9, -- -> 6000
			["Server.MaxMoney"] = 1, -- nicht freigegeben
			["Rewards.Codes.BADCODE"] = { Grant = { Aky = 5 } }, -- Codes nur CR/Kosmetik
			["Events.Rotation"] = { "Truck", "Casino" }, -- unbekannte Option
			Version = 3, -- Metadaten werden ignoriert
		})
		eq(applied, 1, "nur NewsMeanGap übernommen")
		eq(market.NewsMeanGap, 6000, "geklemmt auf Maximum")
		eq(Config.Server.MaxMoney, maxMoney, "MaxMoney unverändert")
		assert(#issues == 3, "3 Probleme erwartet: " .. listText(issues))
		eq(Config.CurrentLive()["Market.NewsMeanGap"], 6000, "CurrentLive")
		-- zweiter Aufruf ersetzt den ersten (Code-Stand + neue Werte)
		Config.ApplyLive({ Fields = { ["Market.NewsMeanGap"] = 10 } })
		eq(market.NewsMeanGap, 300, "auf Minimum geklemmt")
		local rewards: any = Config.Rewards
		if type(rewards.Codes) == "table" then
			local count = Config.ApplyLive({ ["Rewards.Codes.WP1TEST"] = { Grant = { Credits = 5000 } } })
			eq(count, 1, "CR-Code erlaubt")
			eq(rewards.Codes.WP1TEST.Grant.Credits, 5000)
		end
	end)
	Config.ApplyLive({}) -- immer zurück auf den Code-Stand
	eq(market.NewsMeanGap, before, "zurückgesetzt")
	local rewards: any = Config.Rewards
	if type(rewards.Codes) == "table" then
		eq(rewards.Codes.WP1TEST, nil, "Test-Code entfernt")
	end
	eq(next(Config.CurrentLive()), nil, "keine Live-Werte mehr")
	if not ok then
		error(err, 0)
	end
end

-- ---------------------------------------------------------------------
-- Lang
-- ---------------------------------------------------------------------
Tests["Lang.Missing leer"] = function()
	local missing = Lang.Missing()
	assert(#missing == 0, "fehlend: " .. listText(missing))
end

Tests["Lang Pflicht-Schlüssel + Fallback"] = function()
	for _, key in ipairs({
		"core.gameName",
		"core.disclaimer",
		"core.loading",
		"core.error",
		"core.noAnswer",
		"core.studioNoSave",
		"core.localMarket",
		"core.tooFast",
		"core.unknownAction",
		"core.invalid",
	}) do
		assert(Lang.Has(key), "Pflicht-Schlüssel fehlt: " .. key)
	end
	eq(
		Lang.T("de", "core.disclaimer"),
		"Spiel mit Spielgeld. Alle Firmen, Kurse und Nachrichten sind frei erfunden. Spielgeld hat keinen echten "
			.. "Wert und kann nicht ausgezahlt werden. Keine Anlageberatung.",
		"Disclaimer DE wörtlich (§A2)"
	)
	eq(
		Lang.T("en", "core.disclaimer"),
		"Game with play money. All companies, prices and news are fictional. Game money has no real value and "
			.. "cannot be cashed out. Not investment advice.",
		"Disclaimer EN wörtlich (§A2)"
	)
	eq(Lang.T("de", "core.studioNoSave"), "Studio: Fortschritt wird nicht gespeichert")
	eq(Lang.T("de", "gibt.es.nicht"), "gibt.es.nicht", "Schlüssel selbst")
	eq(Lang.T("en", "core.version", "1.0.0"), "Version 1.0.0")
	eq(Lang.T("en", "core.version"), "Version %s", "fehlendes Argument -> Text")
	eq(Lang.Pick("de", { de = "Hallo", en = "Hello" }), "Hallo")
	eq(Lang.Pick("en", { de = "Hallo", en = "Hello" }), "Hello")
end

-- ---------------------------------------------------------------------
-- DataService-Standardstand (§C12)
-- ---------------------------------------------------------------------
local function checkKeys(value: any, path: string, depth: number)
	if type(value) ~= "table" or depth > 10 then
		return
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	local isArray = count == #value
	for key, child in pairs(value) do
		if not isArray then
			assert(type(key) == "string", "Zahl-Schlüssel in Dictionary: " .. path .. "[" .. tostring(key) .. "]")
		end
		checkKeys(child, path .. "." .. tostring(key), depth + 1)
	end
end

Tests["DataService DEFAULT_DATA §C12.1 + JSON"] = function(services: any)
	local dataService = dataServiceOf(services)
	local data = dataService.DefaultData()
	checkKeys(data, "Data", 1)
	eq(data.V, Config.Tech.DataVersion, "V")
	eq(data.Credits, 0)
	eq(data.Depot.Cash, 2500000, "Start-Cash 25.000 AKY in Cent")
	eq(data.Depot.Basis, 2500000, "Start-Basis")
	eq(data.Depot.LastTransferDay, -1)
	eq(data.Depot.AutoTransfer, true)
	eq(#data.Depot.Watch, 1, "eine leere Watchlist")
	eq(data.Garage.Cars.LamCity, true, "Gratis-Auto")
	eq(data.Garage.Active, "LamCity")
	eq(data.Tower.Skin, "GlassBlue")
	eq(data.Prog.Licence, 1)
	eq(data.Prog.Prestige.Stars, 0)
	eq(data.Boosts.X5, 0)
	eq(data.Purchases.RobuxSpent, 0)
	for _, key in ipairs({ "Created", "SavedAt", "LastUtcDay", "Playtime", "Sessions" }) do
		eq(data[key], 0, key)
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	assert(ok, "nicht JSON-fähig: " .. tostring(json))
	assert(#json < 100000, "Standardstand unerwartet groß: " .. #json)
	-- Kopie ist unabhängig
	local other = dataService.DefaultData()
	other.Tower.Vault = 1
	other.Garage.Cars.Extra = true
	eq(dataService.DefaultData().Tower.Vault, 0, "DefaultData liefert Kopien")
	eq(dataService.DefaultData().Garage.Cars.Extra, nil, "tiefe Kopie")
end

Tests["DataService.Migrate repariert (Sanitize, String-Schlüssel, Ringe)"] = function(services: any)
	local dataService = dataServiceOf(services)
	local broken = dataService.DefaultData()
	broken.V = nil
	broken.Credits = 0 / 0
	broken.Stats = "kaputt"
	broken.Tower.Vault = math.huge
	local fixture = broken.Depot -- Attrappe (Kopie von DefaultData), kein echtes Depot
	fixture.Pos[7] = { Q = 10, C = 100, R = 0 } -- Zahl-Schlüssel im Dictionary
	fixture.Pos[19] = { Q = 1, C = 5, R = 0 }
	broken.Prog.Album[3] = true
	broken.Flags.Bad = workspace -- nicht speicherbar
	for i = 1, 130 do
		fixture.Fills[i] = { i, 1, 1, 1, 100, 1, 0 }
	end
	for i = 1, 70 do
		broken.Purchases.Receipts[i] = { Id = "R" .. i, T = i }
	end
	broken.Garage = nil
	dataService.Migrate(broken)
	eq(broken.V, Config.Tech.DataVersion, "V gesetzt")
	eq(broken.Credits, 0, "NaN-Credits repariert")
	eq(type(broken.Stats), "table", "Stats repariert")
	eq(broken.Tower.Vault, 0, "unendlich repariert")
	eq(broken.Depot.Pos[7], nil, "Zahl-Schlüssel entfernt")
	assert(type(broken.Depot.Pos["7"]) == "table" and broken.Depot.Pos["7"].Q == 10, "als String-Schlüssel erhalten")
	assert(type(broken.Depot.Pos["19"]) == "table", "zweiter Schlüssel erhalten")
	eq(broken.Prog.Album["3"], true, "Album-Schlüssel als String")
	eq(broken.Flags.Bad, nil, "Instanz entfernt")
	eq(#broken.Depot.Fills, 100, "Fills-Ring 100")
	eq(broken.Depot.Fills[1][1], 31, "älteste Fills raus")
	eq(#broken.Purchases.Receipts, 60, "Belege 60")
	eq(broken.Purchases.Receipts[1].Id, "R11", "älteste Belege raus")
	eq(broken.Garage.Active, "LamCity", "fehlender Abschnitt ergänzt")
	checkKeys(broken, "Migrated", 1)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(broken)
	end)
	assert(ok, "nach Migrate nicht JSON-fähig: " .. tostring(json))
	-- idempotent
	local snapshot = HttpService:JSONEncode(broken)
	dataService.Migrate(broken)
	eq(HttpService:JSONEncode(broken), snapshot, "Migrate ist idempotent")
end

-- ---------------------------------------------------------------------
-- Scheduler
-- ---------------------------------------------------------------------
Tests["Scheduler.Stats"] = function()
	local stats = Scheduler.Stats()
	assert(type(stats) == "table" and stats._Total ~= nil, "_Total fehlt")
	assert(Util.IsFinite(stats._Total.AvgMs) and Util.IsFinite(stats._Total.MaxMs), "Werte kaputt")
end

-- ---------------------------------------------------------------------
-- Net / Remotes (§C8)
-- ---------------------------------------------------------------------
Tests["Net.RemoteList vollständig = ReplicatedStorage.Remotes"] = function()
	local expected = {
		Notify = "RemoteEvent",
		State = "RemoteEvent",
		Effect = "RemoteEvent",
		Request = "RemoteFunction",
		Admin = "RemoteFunction",
		MarketFrame = "RemoteEvent",
		Market = "RemoteEvent",
		World = "RemoteEvent",
		Replay = "RemoteEvent",
		GrantCash = "RemoteEvent",
	}
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	assert(folder, "ReplicatedStorage.Remotes fehlt")
	local seen: { [string]: boolean } = {}
	for _, spec in ipairs(Net.RemoteList) do
		assert(not seen[spec.Name], "doppelt: " .. spec.Name)
		seen[spec.Name] = true
		eq(spec.Class, expected[spec.Name], "Klasse " .. spec.Name)
		local remote = folder:FindFirstChild(spec.Name)
		assert(remote and remote.ClassName == spec.Class, "fehlt/falsche Klasse: " .. spec.Name)
		assert(Net.Has(spec.Name), "Net.Has " .. spec.Name)
	end
	for name in pairs(expected) do
		assert(seen[name], "fehlt in Net.RemoteList: " .. name)
	end
	eq(#Net.RemoteList, 10, "Anzahl Remotes (§C8)")
	eq(Net.Has("Fire"), false, "keine Shooter-Remotes")
end

-- ---------------------------------------------------------------------
-- AssetSlot (§C14.3)
-- ---------------------------------------------------------------------
Tests["AssetSlot: 0 -> Rezept, Ids -> rbxassetid"] = function()
	local zero = { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }
	eq(AssetSlot.IsSet(zero), false)
	eq(AssetSlot.IsSet(nil), false)
	eq(AssetSlot.IsSet({ MeshId = 12.5, TextureId = 0, Scale = 1, Offset = CFrame.identity }), false, "keine Ganzzahl")
	eq(AssetSlot.IsSet({ MeshId = 123, TextureId = 0, Scale = 1, Offset = CFrame.identity }), true)
	local calls = 0
	local result = AssetSlot.Mesh("Test.Zero", zero, function()
		calls += 1
		local part = Instance.new("Part")
		part.Name = "Rezept"
		return part
	end)
	eq(calls, 1, "Rezept aufgerufen")
	eq(result.Name, "Rezept", "Rezept-Ergebnis")
	result:Destroy()
	local viaNil = AssetSlot.Mesh("Test.Nil", nil, function()
		return Instance.new("Model")
	end)
	eq(viaNil.ClassName, "Model", "nil -> Rezept")
	viaNil:Destroy()
	eq(AssetSlot.Image(0, "fallback"), "fallback")
	eq(AssetSlot.Image(nil), "")
	eq(AssetSlot.Image(123456789012), "rbxassetid://123456789012", "große Id ohne Exponent")
	eq(AssetSlot.SoundId(0), nil)
	eq(AssetSlot.SoundId(42), "rbxassetid://42")
	eq(AssetSlot.KeyOf("Vehicles", "LamCity"), "Vehicles.LamCity")
	local slots = AssetSlot.CollectFromConfig({
		Vehicles = {
			Cars = { { Key = "Fast", Asset = { MeshId = 7, TextureId = 0, Scale = 1, Offset = CFrame.identity } } },
		},
		Tower = {
			Assets = { Crane = { MeshId = 9, TextureId = 3, Scale = 2, Offset = CFrame.identity }, Lobby = zero },
		},
	})
	assert(slots["Vehicles.Fast"] and slots["Vehicles.Fast"].MeshId == 7, "Eintrag mit Key + Asset")
	assert(slots["Tower.Crane"] and slots["Tower.Crane"].MeshId == 9, "Assets-Tabelle")
	eq(slots["Tower.Lobby"], nil, "0-Platz wird nicht vorgeladen")
end

-- ---------------------------------------------------------------------
-- Util / Spring / Format / Clock (Kurzfassung der CLI-Tests, hier mit Roblox-Typen)
-- ---------------------------------------------------------------------
Tests["Util Kernfälle"] = function()
	eq(Util.FormatNumber(1150), "1.15K", "1150")
	eq(Util.FormatNumber(1e33), "1Dc", "1e33")
	eq(Util.FormatNumber(math.huge), "MAX")
	eq(Util.IsFinite(0 / 0), false)
	eq(Util.IsFiniteVector(Vector3.new(0 / 0, 0, 0)), false)
	local now = 0
	local limiter = Util.RateLimiter(2, 1, function()
		return now
	end)
	eq(limiter.Check(1), true)
	eq(limiter.Check(1), true)
	eq(limiter.Check(1), false)
	now = 1
	eq(limiter.Check(1), true)
	local offset = Util.GetDayOffset()
	Util.SetDayOffset(0)
	local ok, err = pcall(function()
		eq(Util.IsoWeek(1791849600), 202642, "IsoWeek 2026-10-13")
	end)
	Util.SetDayOffset(offset)
	if not ok then
		error(err, 0)
	end
	eq(Util.Hash("a"), 1678518572)
end

Tests["Spring konvergiert, NaN-sicher"] = function()
	local spring = Spring.new(Vector3.zero, 25, 0.58)
	spring:SetTarget(Vector3.new(0, 10, 0))
	for _ = 1, 240 do
		spring:Step(1 / 60)
	end
	assert((spring.Position - Vector3.new(0, 10, 0)).Magnitude < 0.05, "Ziel nicht erreicht")
	spring:Impulse(Vector3.new(0 / 0, 0, 0))
	spring:Step(0 / 0)
	spring:Step(5)
	local p = spring.Position
	assert(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN in der Feder")
end

Tests["Format DE/EN"] = function()
	eq(Format.Credits(1250000, "de"), "1,25 Mio.")
	eq(Format.Credits(1250000, "en"), "1.25M")
	eq(Format.Credits(9e15, "de"), "MAX")
	eq(Format.Aky(123456, "de"), "1.234,56 AKY")
	eq(Format.Pct(0.0235, "de", 2, true), "+2,35 %")
	eq(Format.Mult(7.4, "de"), "x7,4")
	eq(Format.Duration(18720, "de"), "5 h 12 min")
	eq(Format.Compact(2.5e15, "en"), "2.5Qa")
end

Tests["Clock: EPOCH, Börsentag, Sommerzeit (Abnahme 6)"] = function()
	eq(Clock.EPOCH, 1767571200)
	eq(Clock.Weekday(Clock.EPOCH), 1, "Montag")
	eq(Clock.DayIndex(1200), 1)
	eq(Clock.DayMinute(600), 10)
	near(Clock.ClockTime(0), 6.5, 1e-9, "Sonnenaufgang")
	eq(Clock.BerlinOffset(1774745940), 3600, "2026-03-29 00:59 UTC")
	eq(Clock.BerlinOffset(1774746000), 7200, "2026-03-29 01:00 UTC")
	eq(Clock.BerlinOffset(1792889940), 7200, "2026-10-25 00:59 UTC")
	eq(Clock.BerlinOffset(1792890000), 3600, "2026-10-25 01:00 UTC")
	eq(Clock.NextBerlin(5, 19, 0, 1791892800), 1792170000, "Crash-Freitag")
	-- Server-Uhr = DateTime (Millisekunden), passt zu os.time()
	assert(math.abs(Clock.Now() - os.time()) <= 5, "Clock.Now weicht von os.time ab")
	local tick = Clock.Tick()
	local fromNow = math.floor(Clock.Now()) - Clock.EPOCH
	assert(fromNow >= tick and fromNow - tick <= 1, "Tick = floor(Now) − EPOCH")
end

Tests["Types ladbar"] = function()
	local module = Shared:FindFirstChild("Types")
	assert(module and module:IsA("ModuleScript"), "Types fehlt")
	eq(type(require(module)), "table", "Types gibt eine Tabelle zurück")
end

return Tests
