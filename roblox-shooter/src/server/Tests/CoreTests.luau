-- =====================================================================
--  CLUTCH CLASH – Selbsttests Core (Server/Tests/CoreTests)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C5.2 (SelfTestService) + C18.
--  Gibt { [testName]: () -> () } zurück; jeder Fehler = FAIL.
--  Prüft: Util (REUSE §14.2-Fälle, Limiter, Datum, Hash), Net-Rundreisen (Look, LookBatch, FX),
--  Remotes vorhanden, Spring, Lang (Missing leer, Fallback), Config.Validate leer, Live-Balance,
--  DEFAULT_DATA (nur String-Schlüssel, JSON-fähig), Scheduler-Statistik.
-- =====================================================================

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Spring = require(Shared:WaitForChild("Spring"))
local Lang = require(Shared:WaitForChild("Lang"))
local Config = require(Shared:WaitForChild("Config"))
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

local function nearVector(actual: Vector3, expected: Vector3, tolerance: number, label: string?)
	if (actual - expected).Magnitude > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Vektor", tostring(expected), tostring(actual)), 2)
	end
end

local function listText(list: { string }): string
	local shown = {}
	for i = 1, math.min(#list, 8) do
		shown[i] = list[i]
	end
	return table.concat(shown, " | ") .. (if #list > 8 then (" … (+%d)"):format(#list - 8) else "")
end

local Tests = {}

-- ---------------------------------------------------------------------
-- Util
-- ---------------------------------------------------------------------
Tests["Util.FormatNumber REUSE §14.2"] = function()
	eq(Util.FormatNumber(1150), "1.15K", "1150")
	eq(Util.FormatNumber(4350000), "4.35M", "4350000")
	eq(Util.FormatNumber(1e33), "1Dc", "1e33")
	eq(Util.FormatNumber(math.huge), "MAX", "math.huge")
	eq(Util.FormatNumber(-math.huge), "-MAX", "-math.huge")
	eq(Util.FormatNumber(-0.5), "0", "-0.5")
	eq(Util.FormatNumber(0 / 0), "0", "NaN")
	eq(Util.FormatNumber(999999), "999K", "999999")
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
	for power = 0, 11 do
		eq(Util.FormatNumber(1000 ^ power), "1" .. suffixes[power + 1], "1e" .. power * 3)
	end
	eq(Util.FormatNumber(1e36), "1000Dc", "1e36")
end

Tests["Util.FormatTime"] = function()
	eq(Util.FormatTime(187), "3:07")
	eq(Util.FormatTime(18720), "5h 12m")
	eq(Util.FormatTime(-1), "0:00")
	eq(Util.FormatTime(0 / 0), "0:00")
end

Tests["Util.DeepCopy + Reconcile"] = function()
	local original = { A = { B = { 1, 2 } } }
	local copy = Util.DeepCopy(original)
	copy.A.B[1] = 5
	eq(original.A.B[1], 1, "Original unverändert")
	local target: any = { X = 1 }
	Util.Reconcile(target, { X = 0, Y = { Z = 2 } })
	eq(target.X, 1)
	eq(target.Y.Z, 2)
end

Tests["Util.WeightedPick 0/NaN nie"] = function()
	local rng = Random.new(42)
	local list = { { Id = "a", Weight = 0 }, { Id = "b", Weight = 0 / 0 }, { Id = "c", Weight = 1 } }
	for _ = 1, 200 do
		local pick = Util.WeightedPick(list, nil, rng)
		eq(pick and pick.Id, "c")
	end
	eq(Util.WeightedPick({ { Weight = 0 } }, nil, rng), nil, "alle 0")
end

Tests["Util.RateLimiter + TokenBucket (künstliche Uhr)"] = function()
	local now = 0
	local function clock(): number
		return now
	end
	local limiter = Util.RateLimiter(2, 1, clock)
	eq(limiter.Check(1), true)
	eq(limiter.Check(1), true)
	eq(limiter.Check(1), false)
	now = 1
	eq(limiter.Check(1), true)
	local bucket = Util.TokenBucket(12, 12, clock)
	for _ = 1, 12 do
		assert(bucket.Take(1), "Marke fehlt")
	end
	eq(bucket.Take(1), false, "leer")
	now = 1.5
	eq(bucket.Take(1, 6), true, "nach 0.5 s 6 Marken")
	eq(bucket.Take(1), false)
end

Tests["Util.IsFinite"] = function()
	eq(Util.IsFinite(3), true)
	eq(Util.IsFinite(0 / 0), false)
	eq(Util.IsFinite(math.huge), false)
	eq(Util.IsFinite("3"), false)
	eq(Util.IsFiniteVector(Vector3.new(1, 2, 3)), true)
	eq(Util.IsFiniteVector(Vector3.new(0 / 0, 0, 0)), false)
	eq(Util.IsFiniteVector(Vector3.new(math.huge, 0, 0)), false)
	eq(Util.IsFiniteVector(5), false)
end

Tests["Util.UtcDay + IsoWeek"] = function()
	local offset = Util.GetDayOffset()
	Util.SetDayOffset(0)
	local ok, err = pcall(function()
		eq(Util.UtcDay(0), 0, "UtcDay(0)")
		eq(Util.IsoWeek(1791676800), 202641, "2026-10-11")
		eq(Util.IsoWeek(1798804800), 202653, "2027-01-01")
		eq(Util.IsoWeek(1735560000), 202501, "2024-12-30")
	end)
	Util.SetDayOffset(offset) -- Debug-Versatz (SkipDay) wiederherstellen
	if not ok then
		error(err, 0)
	end
end

Tests["Util.Hash"] = function()
	eq(Util.Hash(""), 18652613)
	eq(Util.Hash("a"), 1678518572)
	local h = Util.Hash(game.JobId)
	assert(h >= 0 and h < 2 ^ 31 and h % 1 == 0, "Hash außerhalb 0..2^31-1")
end

Tests["Util.Snapshot"] = function()
	local keys = Util.Snapshot({ a = 1, b = 2 })
	eq(#keys, 2)
end

-- ---------------------------------------------------------------------
-- Net
-- ---------------------------------------------------------------------
Tests["Net.Look Rundreise"] = function()
	local b = Net.EncodeLook(-37.4, Net.LookFlags.Ads + Net.LookFlags.Slide, 65537)
	eq(buffer.len(b), 4, "Größe")
	local pitch, flags, seq = Net.DecodeLook(b)
	eq(pitch, -37, "pitch")
	eq(flags, 5, "flags")
	eq(seq, 1, "seq läuft über")
	local clamped = Net.DecodeLook(Net.EncodeLook(120, 0, 0))
	eq(clamped, 80, "pitch geklemmt")
	local nanPitch = Net.DecodeLook(Net.EncodeLook(0 / 0, 0 / 0, 0 / 0))
	eq(nanPitch, 0, "NaN -> 0")
	eq((Net.DecodeLook(buffer.create(3))), nil, "falsche Größe")
	local bad = buffer.create(4)
	buffer.writei8(bad, 0, 100)
	eq((Net.DecodeLook(bad)), nil, "pitch > 80 abgelehnt")
end

Tests["Net.LookBatch Rundreise"] = function()
	local entries = {
		{ Slot = 1, Pitch = 10, Flags = 1 },
		{ Slot = 32, Pitch = -80, Flags = 64 },
		{ Slot = 7, Pitch = 95, Flags = 300 },
	}
	local b = Net.EncodeLookBatch(70000, entries)
	eq(buffer.len(b), 3 + 3 * 3, "Größe")
	local seq, decoded = Net.DecodeLookBatch(b)
	eq(seq, 70000 % 65536, "seq")
	eq(#decoded, 3)
	eq(decoded[1].Slot, 1)
	eq(decoded[1].Pitch, 10)
	eq(decoded[2].Slot, 32)
	eq(decoded[2].Pitch, -80)
	eq(decoded[2].Flags, 64)
	eq(decoded[3].Pitch, 80, "geklemmt")
	eq(decoded[3].Flags, 255, "flags geklemmt")
	local many = {}
	for i = 1, 30 do
		many[i] = { Slot = i, Pitch = 0, Flags = 0 }
	end
	eq(buffer.len(Net.EncodeLookBatch(1, many)), 51, "max. 51 Byte")
	local badSeq, empty = Net.DecodeLookBatch(buffer.create(5))
	eq(badSeq, nil, "kaputtes Paket")
	eq(#empty, 0)
end

Tests["Net.FX Rundreise"] = function()
	local origin = Vector3.new(4000, 100, 4000)
	local entries = {
		{
			Kind = 1,
			Slot = 3,
			Weapon = 2,
			O = origin + Vector3.new(1.25, 5, -3),
			E = origin + Vector3.new(120.04, 2, 80),
		},
		{
			Kind = 2,
			Slot = 9,
			Weapon = 101,
			O = origin + Vector3.new(-3000, 0, 0),
			E = origin + Vector3.new(0, -50.5, 3200),
		},
	}
	local b = Net.EncodeFx(entries, origin)
	eq(buffer.len(b), 1 + 2 * 15, "Größe")
	local decoded = Net.DecodeFx(b, origin)
	assert(decoded, "nicht dekodierbar")
	eq(#decoded, 2)
	eq(decoded[1].Kind, 1)
	eq(decoded[1].Slot, 3)
	eq(decoded[2].Weapon, 101)
	nearVector(decoded[1].O, entries[1].O, 0.06, "O1")
	nearVector(decoded[1].E, entries[1].E, 0.06, "E1")
	nearVector(decoded[2].O, entries[2].O, 0.06, "O2")
	nearVector(decoded[2].E, entries[2].E, 0.06, "E2")
	-- außerhalb ±3276 Studs wird geklemmt, nie Fehler
	local far = Net.DecodeFx(
		Net.EncodeFx({ { Kind = 4, Slot = 1, Weapon = 1, O = origin, E = origin + Vector3.new(9000, 0, 0) } }, origin),
		origin
	)
	assert(far, "weit weg nicht dekodierbar")
	near(far[1].E.X - origin.X, 3276.7, 0.06, "geklemmt")
	-- mehr als 58 Einträge: die ältesten fallen raus, Paket ≤ 871 Byte
	local many = {}
	for i = 1, 60 do
		many[i] = { Kind = 1, Slot = i, Weapon = 1, O = origin, E = origin }
	end
	local big = Net.EncodeFx(many, origin)
	eq(buffer.len(big), 871, "max. 871 Byte")
	local bigDecoded = Net.DecodeFx(big, origin)
	assert(bigDecoded, "großes Paket nicht dekodierbar")
	eq(#bigDecoded, 58)
	eq(bigDecoded[1].Slot, 3, "älteste raus")
	eq(bigDecoded[58].Slot, 60, "neueste drin")
	eq(Net.DecodeFx(buffer.create(2), origin), nil, "kaputtes Paket")
end

Tests["Net.RemoteList = ReplicatedStorage.Remotes"] = function()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	assert(folder, "ReplicatedStorage.Remotes fehlt")
	local seen: { [string]: boolean } = {}
	for _, spec in ipairs(Net.RemoteList) do
		assert(not seen[spec.Name], "doppelt: " .. spec.Name)
		seen[spec.Name] = true
		local remote = folder:FindFirstChild(spec.Name)
		assert(remote and remote.ClassName == spec.Class, "fehlt/falsche Klasse: " .. spec.Name)
	end
	eq(#Net.RemoteList, 13, "Anzahl Remotes (C8)")
	eq(Net.LookFlags.Swing, 64)
end

-- ---------------------------------------------------------------------
-- Spring
-- ---------------------------------------------------------------------
Tests["Spring konvergiert, NaN-sicher"] = function()
	local spring = Spring.new(Vector3.zero, 20, 1)
	spring:SetTarget(Vector3.new(0, 10, 0))
	for _ = 1, 120 do
		spring:Step(1 / 60)
	end
	nearVector(spring.Position, Vector3.new(0, 10, 0), 0.05, "Ziel")
	spring:Impulse(Vector3.new(0 / 0, 0, 0)) -- ignoriert
	spring:Step(0 / 0)
	spring:Step(5) -- auf 1/30 geklemmt
	local p = spring.Position
	assert(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN in der Feder")
end

-- ---------------------------------------------------------------------
-- Lang
-- ---------------------------------------------------------------------
Tests["Lang.Missing leer"] = function()
	local missing = Lang.Missing()
	assert(#missing == 0, "fehlend: " .. listText(missing))
end

Tests["Lang.T Fallback + Format"] = function()
	eq(Lang.T("de", "core.loading"), "Lädt noch…")
	eq(Lang.T("en", "core.loading"), "Loading…")
	eq(Lang.T("de", "gibt.es.nicht"), "gibt.es.nicht", "Schlüssel selbst")
	eq(Lang.T("en", "core.version", "1.0.0"), "Version 1.0.0")
	eq(Lang.T("en", "core.version"), "Version %s", "fehlendes Argument -> Text")
	eq(Lang.Pick("de", { de = "Hallo", en = "Hello" }), "Hallo")
	eq(Lang.Pick("en", { de = "Hallo", en = "Hello" }), "Hello")
	for _, key in ipairs({ "core.gameName", "core.loading", "core.error", "core.noAnswer", "core.studioNoSave" }) do
		assert(Lang.Has(key), "Pflicht-Schlüssel fehlt: " .. key)
	end
end

-- ---------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------
Tests["Config.Validate leer"] = function()
	local errors = Config.Validate()
	assert(#errors == 0, ("%d Problem(e): %s"):format(#errors, listText(errors)))
end

Tests["Config.ApplyBalance klemmt + Not-Aus"] = function()
	local list = Config.Weapons.List
	local fields = Config.Weapons.BalanceFields
	if type(list) ~= "table" or #list == 0 or type(fields) ~= "table" or type(fields.Damage) ~= "table" then
		return -- Waffen (WP3) noch nicht da: nichts zu prüfen
	end
	local key = list[1].Key
	local before = Config.CurrentBalance()
	local ok, err = pcall(function()
		Config.ApplyBalance({
			Version = 999,
			Weapons = { [key] = { Damage = 1e9, Unbekannt = 5 } },
			Disabled = { [key] = true },
		})
		local def = Config.Weapon(key)
		assert(def, "Waffe fehlt nach ApplyBalance")
		eq(def.Damage, fields.Damage[2], "Damage auf Maximum geklemmt")
		eq(def.Enabled, false, "Not-Aus")
		eq(Config.WeaponById(def.Id), def, "WeaponById")
		eq(list[1].Damage ~= 1e9, true, "Basiswerte unverändert")
	end)
	Config.ApplyBalance(before) -- immer zurück auf den alten Stand
	if not ok then
		error(err, 0)
	end
end

-- ---------------------------------------------------------------------
-- DataService-Standardstand (C13)
-- ---------------------------------------------------------------------
local function checkKeys(value: any, path: string, depth: number)
	if type(value) ~= "table" or depth > 8 then
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

Tests["DataService DEFAULT_DATA nur String-Schlüssel + JSON"] = function(services: any)
	local dataService = services and services.DataService
	if not dataService then
		local module = script.Parent.Parent:FindFirstChild("Services")
		module = module and module:FindFirstChild("DataService")
		assert(module and module:IsA("ModuleScript"), "DataService fehlt")
		dataService = require(module) :: any
	end
	local data = dataService.DefaultData()
	checkKeys(data, "Data", 1)
	eq(data.Version, Config.Tech.DataVersion, "Version")
	eq(data.Weapons.Owned.PopRifle, true, "Start-Waffe")
	eq(#data.Loadouts.Presets, 3, "3 Vorlagen")
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	assert(ok, "nicht JSON-fähig: " .. tostring(json))
	assert(#json < 4000000, "zu groß für einen DataStore-Schlüssel")
	-- Migration repariert kaputte Typen
	local broken = dataService.DefaultData()
	broken.Coins = 0 / 0
	broken.Stats = "kaputt"
	broken.Loadouts.Presets[2] = 5
	dataService.Migrate(broken)
	Util.Reconcile(broken, dataService.DefaultData())
	eq(broken.Coins, 0, "NaN-Coins repariert")
	eq(type(broken.Stats), "table", "Stats repariert")
	eq(type(broken.Loadouts.Presets[2]), "table", "Vorlage repariert")
end

-- ---------------------------------------------------------------------
-- Scheduler
-- ---------------------------------------------------------------------
Tests["Scheduler.Stats"] = function()
	local stats = Scheduler.Stats()
	assert(type(stats) == "table" and stats._Total ~= nil, "_Total fehlt")
	assert(Util.IsFinite(stats._Total.AvgMs) and Util.IsFinite(stats._Total.MaxMs), "Werte kaputt")
end

return Tests
