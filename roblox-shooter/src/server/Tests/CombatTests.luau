-- =====================================================================
--  CLUTCH CLASH – Selbsttests Kampf (Server/Tests/CombatTests)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md D (WP3 Tests), C18.
--  Gibt { [testName]: (Services?) -> () } zurück; jeder Fehler = FAIL.
--  Prüft: Hitbox-Strahlen (Kopf/Körper/vorbei/Gleichstand), Damage-Ränder (Start/Ende/Min, Kopf, HeadOnly,
--  Splash), Referenz-TTK B11.6, Spread-Determinismus (#dirs == Pellets, Kegel), Bloom/Kette/Erster Schuss/
--  Rückstoß-Muster, Ballistics (Position/Step/Reflect), Config.Weapons/Combat.Validate leer, Lang combat.* vollständig,
--  synthetische Schuss-Prüfung gegen Test-Puppen in einem Test-Kontext (gültig = angenommen, je Fehlertyp der
--  richtige Reject-Code: TYPE, STATE, RATE, TIME, ORIGIN, LOS, HITBOX, Spread) + exakter Tabellen-Schaden + Pop/Revive.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Spread = require(Shared:WaitForChild("Spread"))
local Hitbox = require(Shared:WaitForChild("Hitbox"))
local Damage = require(Shared:WaitForChild("Damage"))
local Ballistics = require(Shared:WaitForChild("Ballistics"))

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

-- Basiswerte (ohne Live-Balance, damit der Test nicht von Overrides abhängt)
local function base(key: string): any
	for _, def in ipairs(Config.Weapons.List) do
		if def.Key == key then
			return def
		end
	end
	error("Waffe fehlt in Config.Weapons.List: " .. key)
end

local RULES: any = {
	DamageMult = 1,
	HeadOnly = false,
	HeadRadiusMult = 1,
	IntervalMult = 1,
	ReloadMult = 1,
	SpeedMult = 1,
	GravityLift = 0,
	RandomLoadout = false,
	Regen = false,
	UtilityMode = "Charges",
	FriendlyFire = false,
	IgnoreOwnership = true,
}

local tests = {}

-- ---------------------------------------------------------------------
-- HITBOX
-- ---------------------------------------------------------------------
tests.HitboxRays = function()
	local root = CFrame.new(0, 3, 0)
	local head = Vector3.new(0, 4.5, 0)
	local forward = Vector3.new(0, 0, 1)
	local region, dist = Hitbox.Ray(Vector3.new(0, 4.5, -20), forward, 100, root, head, 0.8, 0.35)
	eq(region, "Head", "Kopf-Strahl Region")
	near(dist :: number, 20 - 1.15, 1e-3, "Kopf-Strahl Distanz")
	region, dist = Hitbox.Ray(Vector3.new(0, 2, -20), forward, 100, root, head, 0.8, 0.35)
	eq(region, "Body", "Körper-Strahl Region")
	near(dist :: number, 20 - 1.15, 1e-3, "Körper-Strahl Distanz (Halbmaß 0.8 + Toleranz 0.35)")
	region = Hitbox.Ray(Vector3.new(5, 4.5, -20), forward, 100, root, head, 0.8, 0.35)
	eq(region, nil, "vorbei")
	region = Hitbox.Ray(Vector3.new(0, 4.5, -20), forward, 10, root, head, 0.8, 0.35)
	eq(region, nil, "außer Reichweite")
	region = Hitbox.Ray(Vector3.new(0, 4.5, -20), -forward, 100, root, head, 0.8, 0.35)
	eq(region, nil, "Ziel hinter dem Ursprung")
	-- Gleichstand: Körper ist knapp näher, Kopf gewinnt innerhalb 0.5 Studs
	region = Hitbox.Ray(Vector3.new(0, 3.6, -20), forward, 100, root, head, 0.8, 0.35)
	eq(region, "Head", "Kopf gewinnt Gleichstand")
	-- großer Kopf (BigHeads ×1.6)
	region = Hitbox.Ray(Vector3.new(1.6, 4.5, -20), forward, 100, root, head, 0.8 * 1.6, 0.35)
	eq(region, "Head", "BigHeads-Radius")
	near(Hitbox.PointDistance(Vector3.new(0, 4.5, 0), root, head), 0, 1e-6, "Punkt im Kopf")
	near(Hitbox.PointDistance(Vector3.new(10, 2, 0), root, head), 10 - 1.5, 1e-6, "Punkt neben dem Körper")
end

-- ---------------------------------------------------------------------
-- DAMAGE
-- ---------------------------------------------------------------------
tests.DamageFalloffEdges = function()
	local rifle = base("PopRifle")
	near(Damage.Compute(rifle, 0, "Body", RULES), 15, 1e-9, "Dist 0")
	near(Damage.Compute(rifle, 60, "Body", RULES), 15, 1e-9, "FalloffStart")
	near(Damage.Compute(rifle, 120, "Body", RULES), 15 * (1 + 0.67) / 2, 1e-9, "Mitte")
	near(Damage.Compute(rifle, 180, "Body", RULES), 15 * 0.67, 1e-9, "FalloffEnd")
	near(Damage.Compute(rifle, 5000, "Body", RULES), 15 * 0.67, 1e-9, "Minimum")
	near(Damage.Compute(rifle, 0, "Head", RULES), 22.5, 1e-9, "Kopf ×1.5")
	near(Damage.Compute(rifle, 0, "Body", nil), 15, 1e-9, "ohne Regeln")
	local headOnly = table.clone(RULES)
	headOnly.HeadOnly = true
	eq(Damage.Compute(rifle, 0, "Body", headOnly), 0, "HeadOnly Körper")
	near(Damage.Compute(rifle, 0, "Head", headOnly), 22.5, 1e-9, "HeadOnly Kopf")
	local double = table.clone(RULES)
	double.DamageMult = 2
	near(Damage.Compute(rifle, 0, "Body", double), 30, 1e-9, "DamageMult")
	local rocket = base("PopRocket")
	near(Damage.Splash(rocket, 0), 60, 1e-9, "Splash Mitte")
	near(Damage.Splash(rocket, 5.5), 37.5, 1e-9, "Splash halber Radius")
	eq(Damage.Splash(rocket, 11), 0, "Splash Rand")
	eq(Damage.Splash(rifle, 1), 0, "Splash ohne Projektil")
end

tests.ReferenceTtk = function()
	-- B11.6: Schüsse bis 100 HP (nahe Distanz)
	local function shots(key: string, region: "Head" | "Body"): number
		local def = base(key)
		local per = Damage.Compute(def, 0, region, RULES)
		return math.ceil(100 / per - 1e-9)
	end
	eq(shots("PopRifle", "Body"), 7, "PopRifle Körper")
	eq(shots("PopRifle", "Head"), 5, "PopRifle Kopf")
	eq(shots("BuzzSMG", "Body"), 10, "BuzzSMG Körper")
	eq(shots("BuzzSMG", "Head"), 7, "BuzzSMG Kopf")
	eq(shots("BurstBlaster", "Body"), 6, "BurstBlaster Körper")
	eq(shots("BurstBlaster", "Head"), 4, "BurstBlaster Kopf")
	eq(shots("PipPistol", "Body"), 5, "PipPistol Körper")
	eq(shots("PipPistol", "Head"), 3, "PipPistol Kopf")
	eq(shots("HandCannon", "Body"), 3, "HandCannon Körper")
	eq(shots("Longshot", "Body"), 2, "Longshot Körper")
	eq(shots("Longshot", "Head"), 1, "Longshot Kopf")
	eq(shots("BoxingGloves", "Body"), 3, "BoxingGloves")
	local scatter = base("Scatter")
	local full = 7 * Damage.Compute(scatter, 5, "Body", RULES) + Damage.Compute(scatter, 5, "Head", RULES)
	truthy(full >= 100, "Scatter: 7 Körper + 1 Kopf-Schrot ≤ 10 Studs muss poppen")
	-- Burst: 2 Salven = 0.60 s
	local burst = base("BurstBlaster")
	near(2 * burst.BurstInterval + burst.Interval + 2 * burst.BurstInterval, 0.60, 1e-9, "BurstBlaster Zeit")
end

-- ---------------------------------------------------------------------
-- SPREAD
-- ---------------------------------------------------------------------
tests.SpreadDeterminism = function()
	local scatter = base("Scatter")
	local aim = Vector3.new(0.3, 0.1, -1).Unit
	local seed = Spread.Seed(123456, 42)
	eq(seed, Spread.Seed(123456, 42), "Seed deterministisch")
	eq(seed % 1, 0, "Seed ganzzahlig")
	truthy(seed >= 1 and seed <= 2147483647, "Seed im Bereich")
	truthy(seed ~= Spread.Seed(123456, 43), "andere shotId -> anderer Seed")
	local a = Spread.Directions(aim, scatter, 6, seed)
	local b = Spread.Directions(aim, scatter, 6, seed)
	eq(#a, scatter.Pellets, "#dirs == Pellets")
	for i = 1, #a do
		eq(a[i], b[i], "gleicher Seed -> gleiche Richtung " .. i)
		near(a[i].Magnitude, 1, 1e-6, "Einheitsvektor")
		local angle = math.deg(math.acos(math.clamp(a[i]:Dot(aim), -1, 1)))
		truthy(angle <= 6 + 1e-4, "Richtung im Kegel (" .. angle .. "°)")
	end
	local c = Spread.Directions(aim, scatter, 6, Spread.Seed(123456, 43))
	truthy(c[1] ~= a[1], "anderer Seed -> andere Richtungen")
	local zero = Spread.Directions(aim, base("PopRifle"), 0, seed)
	eq(#zero, 1, "Gewehr: 1 Strahl")
	near((zero[1] - aim).Magnitude, 0, 1e-6, "Spread 0 = Zielrichtung")
end

tests.SpreadBloomChainRecoil = function()
	local rifle = base("PopRifle")
	near(Spread.Bloom(rifle, {}, 1), 0, 1e-9, "erster Schuss ohne Bloom")
	near(Spread.Bloom(rifle, { 0.7, 0.8, 0.9 }, 1.0), 0.45, 1e-9, "Kette 3 × 0.15")
	eq(Spread.Chain(rifle, { 0.5, 0.9 }, 1.0), 1, "Kette reißt bei Abstand > Interval × 1.6")
	near(Spread.Bloom(rifle, table.create(30, 0), 0.05), 0, 1e-9, "spätere Einträge zählen nicht")
	local many: { number } = {}
	for i = 1, 20 do
		many[i] = i * 0.1
	end
	near(Spread.Bloom(rifle, many, 2.1), 1.5, 1e-9, "BloomMax")
	near(Spread.FirstShot(rifle, {}, 1), 0.5, 1e-9, "Erster Schuss präzise")
	near(Spread.FirstShot(rifle, { 0.95 }, 1), 1, 1e-9, "Dauerfeuer ohne Bonus")
	near(Spread.FirstShot(base("Scatter"), {}, 1), 1, 1e-9, "ohne FirstShotMult")
	local p1, y1 = Spread.Recoil(rifle, 1)
	near(p1, 0.32, 1e-9, "Muster Schuss 1 Pitch")
	near(y1, 0, 1e-9, "Muster Schuss 1 Yaw")
	local p15, y15 = Spread.Recoil(rifle, 15) -- 14 Einträge, Schleife ab 8
	near(p15, 0.32 * 0.9, 1e-9, "Muster-Schleife Pitch")
	near(y15, 0.12 * -0.4, 1e-9, "Muster-Schleife Yaw")
	local ps, ys = Spread.Recoil(base("BoxingGloves"), 3, 99)
	eq(ps, 0, "kein Rückstoß bei Nahkampf")
	eq(ys, 0, "kein Seitenkick bei Nahkampf")
	local hipMin = Spread.MinScale(rifle, false, 0, false)
	near(hipMin, 2.0, 1e-9, "MinScale Hüfte")
	near(Spread.MinScale(rifle, true, 0, false), 0.5, 1e-9, "MinScale ADS")
	near(Spread.MinScale(rifle, false, 20, true), 2.0 + 1.0 + 3, 1e-9, "MinScale bewegt + Luft")
end

-- Lernbare Rückstoß-Muster (SKILL-WUENSCHE): jede Fernkampfwaffe mit Muster folgt beim Dauerfeuer Schuss
-- für Schuss demselben Muster – Index = Spread.Chain + 1, dieselbe Kette, die der Server für Bloom und
-- Erster-Schuss-Genauigkeit benutzt (Client = Server). Seed spielt beim Muster keine Rolle.
tests.RecoilPatternsLearnable = function()
	for _, def in ipairs(Config.Weapons.List) do
		local pattern = def.RecoilPattern
		if type(pattern) ~= "table" or (def.Kind ~= "Hitscan" and def.Kind ~= "Projectile") then
			continue
		end
		local interval = if def.FireMode == "Burst" and def.BurstInterval then def.BurstInterval else def.Interval
		local times: { number } = {}
		for shot = 1, #pattern + 3 do
			local t = shot * interval
			local index = Spread.Chain(def, times, t) + 1
			eq(index, shot, def.Key .. ": Muster-Index beim Dauerfeuer")
			local p1, y1 = Spread.Recoil(def, index, 1)
			local p2, y2 = Spread.Recoil(def, index, 987654)
			eq(p1, p2, def.Key .. ": Muster-Pitch unabhängig vom Seed")
			eq(y1, y2, def.Key .. ": Muster-Yaw unabhängig vom Seed")
			truthy(p1 >= 0, def.Key .. ": Pitch nie nach unten")
			truthy(math.abs(y1) <= def.RecoilYaw * 1.5 + 1e-9, def.Key .. ": Seitenkick begrenzt")
			table.insert(times, t)
		end
		-- Antippen (Pause > Interval × 1.6) beginnt das Muster neu
		eq(Spread.Chain(def, { 0 }, def.Interval * 1.7) + 1, 1, def.Key .. ": Antippen = Muster von vorn")
	end
end

-- ---------------------------------------------------------------------
-- BALLISTICS
-- ---------------------------------------------------------------------
tests.BallisticsMath = function()
	local p0 = Vector3.new(0, 10, 0)
	local v = Vector3.new(10, 20, 0)
	local p = Ballistics.Position(p0, v, 90, 0.5)
	near((p - Vector3.new(5, 10 + 10 - 0.5 * 90 * 0.25, 0)).Magnitude, 0, 1e-9, "Position")
	local sp, sv = Ballistics.Step(p0, v, 90, 0.5)
	near((sp - p).Magnitude, 0, 1e-9, "Step = Position")
	near((sv - Vector3.new(10, 20 - 45, 0)).Magnitude, 0, 1e-9, "Step Geschwindigkeit")
	local r = Ballistics.Reflect(Vector3.new(10, -10, 0), Vector3.new(0, 1, 0), 0.5)
	near((r - Vector3.new(10 * Ballistics.TangentKeep, 5, 0)).Magnitude, 0, 1e-9, "Reflect")
	local straight = Ballistics.Position(p0, Vector3.new(0, 0, -120), 0, 2)
	near((straight - Vector3.new(0, 10, -240)).Magnitude, 0, 1e-9, "Rakete g = 0")
end

-- ---------------------------------------------------------------------
-- CONFIG & LANG
-- ---------------------------------------------------------------------
tests.ConfigWeaponsCombatValid = function()
	local weapons: any = Config.Weapons
	local combat: any = Config.Combat
	local errors = weapons.Validate(Config)
	for _, e in ipairs(combat.Validate(Config)) do
		table.insert(errors, e)
	end
	if #errors > 0 then
		error(("%d Fehler: %s"):format(#errors, table.concat(errors, " | ")))
	end
	local count, admin = 0, 0
	for _, def in ipairs(weapons.List) do
		if def.AdminOnly then
			admin += 1
		else
			count += 1
		end
	end
	eq(count, 15, "15 Waffen")
	eq(admin, 4, "4 Admin-Waffen")
	local price = 0
	for _, def in ipairs(weapons.List) do
		if not def.AdminOnly and not def.Free then
			price += def.Price
		end
	end
	eq(price, 13200, "Preise gesamt (B11.5)")
end

tests.LangCombatComplete = function()
	local module = Shared:WaitForChild("Lang"):WaitForChild("Combat")
	local texts: any = require(module)
	for _, key in ipairs({ "combat.popped", "combat.hpLeft", "combat.dealt" }) do
		truthy(type(texts.de[key]) == "string" and type(texts.en[key]) == "string", "Pflicht-Schlüssel fehlt: " .. key)
	end
	for key in pairs(texts.de) do
		truthy(texts.en[key] ~= nil, "en fehlt: " .. key)
		truthy(string.sub(key, 1, 7) == "combat.", "Präfix: " .. key)
	end
	for key in pairs(texts.en) do
		truthy(texts.de[key] ~= nil, "de fehlt: " .. key)
	end
end

-- ---------------------------------------------------------------------
-- SYNTHETISCHE SCHUSS-PRÜFUNG (Test-Kontext mit Puppen)
-- ---------------------------------------------------------------------
local BASE = Vector3.new(0, 1500, 14000) -- weit weg von Lobby/Arenen, über FallenPartsDestroyHeight

local function makeRig(parent: Instance, name: string, pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = false
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.CanCollide = false
	head.Size = Vector3.new(1, 1, 1)
	head.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	head.Parent = model
	model.PrimaryPart = root
	model.Parent = parent
	return model
end

local function withTestContext(Services: any, fn: (env: any) -> ())
	assert(type(Services) == "table", "Services fehlen")
	local CombatService = Services.CombatService
	local WeaponService = Services.WeaponService
	assert(CombatService and WeaponService and Services.HistoryService, "WP3-Services fehlen")
	local folder = Instance.new("Folder")
	folder.Name = "CC_CombatTest"
	local map = Instance.new("Model")
	map.Name = "Map"
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.Size = Vector3.new(1, 30, 30)
	wall.CFrame = CFrame.new(BASE + Vector3.new(30, 0, 0))
	wall.Parent = map
	map.Parent = folder
	local params = RaycastParams.new()
	params.IncludeInstances = { map } -- wie ArenaService.MapParams: nur IncludeInstances
	local ctx = ("Test_%d"):format(math.floor(os.clock() * 1000) % 1000000)
	local arena: any = {
		Slot = 0,
		Key = "CombatTest",
		BuildId = 0,
		Model = map,
		Origin = CFrame.new(BASE),
		Spawns = { A = {}, B = {}, FFA = {} },
		Zone = BASE,
		ZoneRadius = 8,
		KillY = BASE.Y - 400,
		Vault = CFrame.new(BASE - Vector3.new(0, 100, 0)),
		Nav = { Nodes = {}, Edges = {} },
		MapParams = params,
	}
	local shooterModel = makeRig(folder, "TestShooter", BASE)
	local dummyModel = makeRig(folder, "TestDummy", BASE + Vector3.new(0, 0, -40))
	local wallModel = makeRig(folder, "TestWallDummy", BASE + Vector3.new(60, 0, 0))
	folder.Parent = workspace

	local registered: { any } = {}
	local ok, err = pcall(function()
		CombatService.RegisterContext({
			Ctx = ctx,
			Arena = arena,
			Rules = table.clone(RULES),
			Recipients = function()
				return {}
			end,
			MatchId = nil,
		})
		local loadout: any = table.clone(Config.Weapons.DefaultLoadout)
		local function add(kind: string, model: Model, team: number, slot: number, name: string): any
			local c = CombatService.NewCombatant({
				Kind = kind :: any,
				Model = model,
				Ctx = ctx,
				Team = team,
				Slot = slot,
				Name = name,
				Loadout = loadout,
			})
			CombatService.Register(c)
			table.insert(registered, c)
			return c
		end
		local env = {
			Ctx = ctx,
			Shooter = add("Bot", shooterModel, 1, 1, "TestShooter"),
			Dummy = add("Dummy", dummyModel, 2, 2, "TestDummy"),
			WallDummy = add("Dummy", wallModel, 2, 3, "TestWallDummy"),
		}
		env.Shooter.Salt = 4242
		fn(env)
	end)
	for _, c in ipairs(registered) do
		pcall(CombatService.Unregister, c)
	end
	pcall(CombatService.UnregisterContext, ctx)
	folder:Destroy()
	if not ok then
		error(err, 0)
	end
end

tests.FireValidationCodes = function(Services: any)
	withTestContext(Services, function(env)
		local WeaponService = Services.WeaponService
		local shooter, dummy, wallDummy = env.Shooter, env.Dummy, env.WallDummy
		local rifle = Config.Weapon("PopRifle") :: any
		local recv = 1000
		local function reset()
			WeaponService.Forget(shooter) -- Eimer + Empfangsabstand
			shooter.LastShotT = 0
			table.clear(shooter.ShotTimes)
			shooter.Ammo.Primary.Mag = 30
			shooter.Ammo.Primary.ReloadUntil = 0
		end
		local function fire(overrides: { [string]: any }): (boolean, string?)
			recv += 10
			local origin = shooter.Head.Position
			local bodyCenter = dummy.Root.Position - Vector3.new(0, 1, 0)
			local packet: any = {
				ShotId = shooter.LastShotId + 1,
				WeaponId = rifle.Id,
				T = workspace:GetServerTimeNow() - 0.05,
				Origin = origin,
				Aim = (bodyCenter - origin).Unit,
				Scale = 0,
				Targets = { dummy.Id },
			}
			for key, value in pairs(overrides) do
				packet[key] = value
			end
			if overrides.Targets == false then
				packet.Targets = {}
			end
			return WeaponService.TestFire(shooter, packet, {
				Recv = recv,
				Now = workspace:GetServerTimeNow(),
				Ping = 0.05,
				DryRun = overrides.DryRun ~= false,
			})
		end

		reset()
		local ok, code = fire({})
		eq(ok, true, "gültiger Schuss angenommen (" .. tostring(code) .. ")")

		reset()
		eq(select(2, fire({ Aim = Vector3.new(0, 0, -2) })), "TYPE", "Aim nicht normiert")
		eq(select(2, fire({ Scale = 0 / 0 })), "TYPE", "NaN")
		eq(select(2, fire({ Targets = false })), "TYPE", "#targets ~= Pellets")
		eq(select(2, fire({ WeaponId = 99 })), "TYPE", "falsche Waffe")
		eq(select(2, fire({ Origin = "kaputt" })), "TYPE", "falscher Typ")

		reset()
		eq(select(2, fire({ ShotId = shooter.LastShotId })), "STATE", "alte shotId")
		eq(select(2, fire({ ShotId = shooter.LastShotId + 10 })), "STATE", "shotId-Sprung > 4")

		reset()
		local t0 = workspace:GetServerTimeNow() - 0.05
		eq(select(1, fire({ T = t0 })), true, "erster Schuss der Salve")
		eq(select(2, fire({ T = t0 + 0.01 })), "RATE", "zu schnell (Intervall)")

		reset()
		eq(select(2, fire({ T = workspace:GetServerTimeNow() + 0.5 })), "TIME", "Zeitstempel in der Zukunft")

		reset()
		eq(
			select(2, fire({ Origin = shooter.Head.Position + Vector3.new(20, 0, 0) })),
			"ORIGIN",
			"Ursprung 20 Studs weg"
		)

		reset()
		local origin = shooter.Head.Position
		local wallBody = wallDummy.Root.Position - Vector3.new(0, 1, 0)
		eq(select(2, fire({ Aim = (wallBody - origin).Unit, Targets = { wallDummy.Id } })), "LOS", "durch die Wand")

		reset()
		eq(select(2, fire({ Aim = Vector3.new(0, 1, 0) })), "HITBOX", "Ziel behauptet, Strahl vorbei")

		-- Falscher Spread: Client behauptet 0°, Server erzwingt die Hüft-Untergrenze -> andere Strahlen
		reset()
		shooter.Loadout = table.clone(shooter.Loadout)
		shooter.Loadout.Primary = "Longshot"
		local longshot = Config.Weapon("Longshot") :: any
		shooter.Ammo.Primary.Mag = longshot.Mag
		local aimHead = (dummy.Head.Position - origin).Unit
		local minScale = Spread.MinScale(longshot, false, 0, false)
		local chosen: number? = nil
		for k = shooter.LastShotId + 1, shooter.LastShotId + 400 do
			local dirs = Spread.Directions(aimHead, longshot, minScale, Spread.Seed(shooter.Salt, k))
			local region =
				Hitbox.Ray(origin, dirs[1], longshot.Range, dummy.Root.CFrame, dummy.Head.Position, 0.8, 0.35)
			if region == nil then
				chosen = k
				break
			end
		end
		truthy(chosen ~= nil, "keine verfehlende shotId gefunden")
		shooter.LastShotId = (chosen :: number) - 1
		eq(
			select(2, fire({ WeaponId = longshot.Id, Aim = aimHead, Scale = 0 })),
			"HITBOX",
			"falscher Spread wird verworfen"
		)
		shooter.Loadout.Primary = "PopRifle"

		-- Echter Schaden: Puppe nimmt exakt den Tabellen-Schaden (Körper, < FalloffStart)
		reset()
		shooter.Ammo.Primary.Mag = rifle.Mag
		local before = dummy.Hp
		ok, code = fire({ DryRun = false })
		eq(ok, true, "Schuss mit Schaden angenommen (" .. tostring(code) .. ")")
		near(before - dummy.Hp, Damage.Compute(rifle, 40, "Body", RULES), 1e-6, "Tabellen-Schaden")
		eq(shooter.Ammo.Primary.Mag, rifle.Mag - 1, "Munition −1")
	end)
end

tests.PopAndRevive = function(Services: any)
	withTestContext(Services, function(env)
		local CombatService = Services.CombatService
		local shooter, dummy = env.Shooter, env.Dummy
		local dealt, killed = CombatService.ApplyDamage(shooter, dummy, 30, {
			WeaponKey = "PopRifle",
			Head = false,
			Kind = "Hitscan",
			Dist = 40,
			From = shooter.Head.Position,
		})
		eq(dealt, 30, "Schaden")
		eq(killed, false, "lebt noch")
		eq(dummy.Model:GetAttribute("Hp"), 70, "Attribut Hp")
		CombatService.SetShield(dummy, 5)
		eq(
			select(
				1,
				CombatService.ApplyDamage(shooter, dummy, 30, {
					WeaponKey = "PopRifle",
					Head = false,
					Kind = "Hitscan",
					Dist = 40,
					From = shooter.Head.Position,
				})
			),
			0,
			"Spawn-Schutz"
		)
		CombatService.SetShield(dummy, 0)
		dealt, killed = CombatService.ApplyDamage(shooter, dummy, 500, {
			WeaponKey = "PopRifle",
			Head = true,
			Kind = "Hitscan",
			Dist = 40,
			From = shooter.Head.Position,
		})
		eq(dealt, 70, "Rest-Leben")
		eq(killed, true, "gepoppt")
		eq(dummy.Alive, false, "Alive = false")
		eq(dummy.Model:GetAttribute("Alive"), false, "Attribut Alive")
		local recap = CombatService.Recap(dummy.Id)
		truthy(recap ~= nil, "Rückblick vorhanden")
		eq(recap.KillerId, shooter.Id, "Killer im Rückblick")
		eq(#recap.Taken, 2, "2 Treffer im Rückblick")
		eq(CombatService.RoundDamage(env.Ctx)[shooter.Id], 100, "Rundenschaden")
		CombatService.Revive(dummy, dummy.Root.CFrame)
		eq(dummy.Alive, true, "wiederbelebt")
		eq(dummy.Hp, dummy.MaxHp, "volles Leben")
		CombatService.ResetRound(env.Ctx)
		eq(CombatService.Recap(dummy.Id), nil, "ResetRound leert den Rückblick")
	end)
end

return tests
