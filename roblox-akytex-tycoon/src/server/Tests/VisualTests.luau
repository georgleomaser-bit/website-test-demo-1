-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Turm-Optik & Lifestyle (Server/Tests/VisualTests)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §D WP8 "Abnahme"/"Tests": Teilebudget je
--  Stufe (Hülle ≤ 8/Etage, Krone ≤ 60, Plot-Ausstattung ≤ 40, 10 Tower ≤ 4.600), Interior ≤ 150 Parts je Etage,
--  Layout-Rundreise ≤ 2 KB, Rezepte deterministisch; dazu Deko-/Lifestyle-Konfiguration, Uhren 6–10 Parts
--  (Massless, ohne Kollision), Lager-Logik (Nehmen/Zurückgeben/Rabatt), Asset-Platz 0 -> Code-Rezept.
--  SelfTestService lädt dieses Modul; jeder Fehler = FAIL. Keine Spieler, keine echten Spielstände.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local TowerModels = require(Shared:WaitForChild("TowerModels"))
local DecorModels = require(Shared:WaitForChild("DecorModels"))
local LifestyleModels = require(Shared:WaitForChild("LifestyleModels"))

local ROOMS =
	{ "Office", "Desk", "Cafe", "Garage", "Marketing", "Vault", "Lab", "Server", "Lounge", "BotLab", "Penthouse" }
local STAGE_LAST = { 1, 3, 6, 9, 13, 17, 21, 25, 30, 36, 43, 50 }

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

local function same(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function serviceModule(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

-- die 8 größten Deko-Teile (schlimmster Fall für das Interior-Budget)
local function biggestDecor(): { string }
	local list = {}
	for _, entry in ipairs(Config.Decor.Items) do
		table.insert(list, { Key = entry.Key, N = #DecorModels.Specs(entry.Key) })
	end
	table.sort(list, function(a, b)
		return a.N > b.N
	end)
	local out = {}
	for i = 1, math.min(8, #list) do
		out[i] = list[i].Key
	end
	return out
end

local Tests = {}

-- 1) Hülle: ≤ 8 Parts je Etage, Krone ≤ 60, Plot-Ausstattung ≤ 40, ein Tower ≤ 460, 10 Tower ≤ 4.600 (§B3)
function Tests.ShellBudgetPerStage()
	local limits = TowerModels.LIMITS
	local worst = 0
	for stage, last in ipairs(STAGE_LAST) do
		local first = if stage == 1 then 1 else STAGE_LAST[stage - 1] + 1
		for floors = first, last do
			local total, maxFloor, _spine, crown, site = TowerModels.Count(stage, floors)
			truthy(
				maxFloor <= limits.ShellPerFloor,
				("Stufe %d/%d Etagen: %d Parts je Etage"):format(stage, floors, maxFloor)
			)
			truthy(crown <= limits.Crown, ("Stufe %d: Krone %d Parts"):format(stage, crown))
			truthy(site <= limits.Site, ("Stufe %d: Plot-Ausstattung %d Parts"):format(stage, site))
			truthy(total <= limits.TowerTotal, ("Stufe %d/%d Etagen: %d Parts gesamt"):format(stage, floors, total))
			worst = math.max(worst, total)
		end
	end
	truthy(worst * 10 <= limits.AllTowers, ("10 Tower × %d Parts > 4.600"):format(worst))
	truthy(#TowerModels.Site(1, 0, "GlassBlue", "Accent") <= limits.Site, "Bauplatz-Ausstattung zu groß")
end

-- 2) Jede Fassade/jedes Neon baut fehlerfrei und im Budget
function Tests.SkinsAndNeonBuild()
	for _, skin in ipairs(TowerModels.Skins()) do
		for _, neon in ipairs(Config.Tower.Neon) do
			for _, stage in ipairs({ 1, 4, 8, 12 }) do
				local n = #TowerModels.Shell(stage, STAGE_LAST[stage], skin, neon.Key)
				truthy(n >= 5 and n <= 8, ("Hülle %s/%s Stufe %d: %d Parts"):format(skin, neon.Key, stage, n))
			end
		end
	end
	for _, crown in ipairs(Config.Tower.Crowns) do
		truthy(#TowerModels.Crown(12, crown.Key, 50, "GlassBlue", "Accent") <= 60, "Krone " .. crown.Key .. " > 60")
	end
end

-- 3) Interior ≤ 150 Parts je Etage für alle Räume × Stufen × Grundrisse (volles Personal, größte Deko)
function Tests.InteriorBudget()
	local decor = biggestDecor()
	for _, room in ipairs(ROOMS) do
		for level = 1, 5 do
			for _, footprint in ipairs({ 40, 48, 52, 56 }) do
				for _, floor in ipairs({ 1, 2, 50 }) do
					local n =
						#TowerModels.Interior(room, level, { "Quant", "Senior", "Analyst" }, decor, footprint, floor)
					truthy(n <= TowerModels.LIMITS.Interior, ("%s L%d %d: %d Parts"):format(room, level, footprint, n))
					truthy(n >= 10, ("%s L%d: zu leer (%d)"):format(room, level, n))
				end
			end
		end
	end
end

-- 4) Rezepte deterministisch (gleiche Eingabe -> gleiche Specs auf Server und Client)
function Tests.RecipesDeterministic()
	truthy(same(TowerModels.Shell(9, 27, "HoloPrism", "Cyan"), TowerModels.Shell(9, 27, "HoloPrism", "Cyan")), "Shell")
	truthy(same(TowerModels.Spine(12, 50, "Obsidian", "Gold"), TowerModels.Spine(12, 50, "Obsidian", "Gold")), "Spine")
	truthy(
		same(TowerModels.Crown(10, "Gold", 33, "Polar", "Up"), TowerModels.Crown(10, "Gold", 33, "Polar", "Up")),
		"Crown"
	)
	local a = TowerModels.Interior("Desk", 4, { "Intern" }, { "DeskStartup", "", "AquariumSmall" }, 56, 7)
	local b = TowerModels.Interior("Desk", 4, { "Intern" }, { "DeskStartup", "", "AquariumSmall" }, 56, 7)
	truthy(same(a, b), "Interior")
	truthy(same(DecorModels.Specs("Chandelier"), DecorModels.SpecsFor(Config.Decor.ByKey.Chandelier.Recipe)), "Deko")
end

-- 5) Layout-Rundreise (§C12.3) und Obergrenze 2 KB
function Tests.LayoutRoundTrip()
	local floors = {}
	for i = 1, 50 do
		floors[i] = {
			R = if i == 50 then "Penthouse" elseif i % 3 == 0 then "Cafe" else "Desk",
			L = (i % 5) + 1,
			S = { "Quant", "Senior", "Intern" },
			D = { "TrophyDiamond", "", "KoiPond" },
		}
	end
	-- Penthouse: 8 Plätze (§B4.8)
	floors[50].D = { "TrophyDiamond", "SofaVelvet", "", "Bonsai", "GlobeBrass", "", "RugGeo", "NeonTree" }
	local text = TowerModels.EncodeLayout(floors, { 2, 4 })
	truthy(#text <= TowerModels.LIMITS.LayoutBytes, ("Layout %d Bytes"):format(#text))
	local decoded = TowerModels.DecodeLayout(text)
	eq(#decoded, 50, "Etagen")
	eq(decoded[2].Private, true, "Privat 2")
	eq(decoded[3].Private, false, "Privat 3")
	eq(decoded[3].Room, "Cafe", "Raum 3")
	eq(decoded[1].Level, 2, "Stufe 1")
	eq(decoded[1].Staff[1], "Quant", "Personal")
	eq(decoded[1].Decor[2], "", "leerer Platz")
	eq(decoded[1].Decor[3], "KoiPond", "Deko 3")
	eq(decoded[50].Room, "Penthouse", "Penthouse")
	eq(decoded[50].Decor[8], "NeonTree", "Penthouse-Platz 8")
	eq(decoded[50].Decor[1], "TrophyDiamond", "Penthouse-Platz 1")
	-- kaputte Eingaben -> nie ein Fehler
	truthy(type(TowerModels.DecodeLayout("x;;!:9:ZZ:,,,")) == "table", "kaputtes Layout")
	eq(#TowerModels.DecodeLayout(""), 0, "leeres Layout")
	-- extremer Fall: TowerVisualService kürzt notfalls die Deko (Raum/Stufe/Personal bleiben)
	local tvs = serviceModule(nil, "TowerVisualService")
	local huge = {}
	for i = 1, 50 do
		huge[i] = { R = "Penthouse", L = 5, S = { "Quant", "Quant", "Quant" }, D = table.create(16, "TrophyDiamond") }
	end
	local trimmed = tvs._Test.Layout({ Floors = huge, Private = { 1, 2, 3, 4, 5 } })
	truthy(#trimmed <= 2048, "gekürztes Layout > 2 KB")
	eq(#TowerModels.DecodeLayout(trimmed), 50, "gekürztes Layout behält alle Etagen")
end

-- 6) Deko-Konfiguration: 68 Teile, jedes Rezept existiert und bleibt klein
function Tests.DecorConfigAndRecipes()
	local errors = Config.Decor.Validate(Config)
	eq(#errors, 0, "Config.Decor.Validate: " .. (errors[1] or ""))
	eq(#Config.Decor.Items, 68, "Deko-Teile")
	for _, entry in ipairs(Config.Decor.Items) do
		truthy(DecorModels.Has(entry.Recipe.Kind), "Rezept fehlt: " .. entry.Recipe.Kind)
		local n = #DecorModels.Specs(entry.Key)
		truthy(n >= 3 and n <= 14, ("%s: %d Parts"):format(entry.Key, n))
		eq(Config.Decor[entry.Key], entry, "Config.Decor[key] (§C12.3)")
	end
end

-- 7) Asset-Platz 0 -> Code-Rezept (Model mit Teilen, Pivot im Ursprung)
function Tests.DecorBuildUsesRecipe()
	local model = DecorModels.Build("GlobeBrass")
	truthy(model:IsA("Model"), "Model erwartet")
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	eq(parts, #DecorModels.Specs("GlobeBrass"), "Teile im Rezept-Model")
	model:Destroy()
end

-- 8) Uhren: 6–10 Parts, unverankert, Massless, ohne Kollision/Abfrage/Berührung, Zeiger-Welds
function Tests.WatchesAndAccessories()
	local errors = Config.Lifestyle.Validate(Config)
	eq(#errors, 0, "Config.Lifestyle.Validate: " .. (errors[1] or ""))
	for _, entry in ipairs(Config.Lifestyle.Watches) do
		local model = LifestyleModels.Watch(entry.Key)
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				truthy(
					not d.Anchored and d.Massless and not d.CanCollide and not d.CanQuery and not d.CanTouch,
					entry.Key .. ": Physik"
				)
			end
		end
		truthy(parts >= 6 and parts <= 10, ("%s: %d Parts"):format(entry.Key, parts))
		truthy(model.PrimaryPart ~= nil, entry.Key .. ": PrimaryPart")
		truthy(
			model:FindFirstChild("HourWeld", true) ~= nil and model:FindFirstChild("MinuteWeld", true) ~= nil,
			entry.Key .. ": Zeiger"
		)
		model:Destroy()
	end
	for _, entry in ipairs(Config.Lifestyle.Accessories) do
		local model = LifestyleModels.Accessory(entry.Key)
		truthy(model.PrimaryPart ~= nil, entry.Key .. ": PrimaryPart")
		model:Destroy()
	end
end

-- 9) Lager-Logik (TakeDecor/ReturnDecor-Kern), Komfort, Rabatt
function Tests.StorageCore()
	local core = serviceModule(nil, "LifestyleService")._Test.Core
	local data: any = { Life = {}, Storage = { Decor = { Bonsai = 2, Kaputt = 0 / 0 } }, Tower = { Floors = {} } }
	core.Repair(data)
	eq(data.Storage.Decor.Kaputt, nil, "NaN entfernt")
	eq(core.Take(data, "Bonsai"), true, "nehmen 1")
	eq(core.Take(data, "Bonsai"), true, "nehmen 2")
	eq(core.Take(data, "Bonsai"), false, "Lager leer")
	eq(data.Storage.Decor.Bonsai, nil, "Schlüssel bei 0 entfernt")
	eq(core.Give(data, "Bonsai", 3), true, "zurück")
	eq(core.Count(data, "Bonsai"), 3, "Anzahl")
	eq(core.Give(data, "Bonsai", 1.5), false, "nur ganze Stück")
	data.Tower.Floors = {
		{ R = "Office", L = 1, S = {}, D = { "Bonsai", "", "Gong" } },
		{ R = "Cafe", L = 1, S = {}, D = { "Bonsai" } },
	}
	local placed = core.Placed(data)
	eq(placed.Bonsai, 2, "platziert")
	eq(placed.Gong, 1, "platziert Gong")
	eq(core.Discount(0), 0, "kein Rabatt")
	eq(core.Discount(5), 0.25, "Vorstand 5 = −25 %")
	eq(core.Discount(99), 0.25, "Rabatt geklemmt")
	eq(core.Price(50000, 0.25), 37500, "Preis mit Rabatt")
	eq(core.Price(1, 0.9), 1, "Mindestpreis 1 CR")
	data.Life = {
		Watches = { "Copper" },
		Accessories = { TiePin = true },
		Equipped = { Watch = 7, Acc = { "A", "A", "B", "C", "D" } },
	}
	core.Repair(data)
	eq(data.Life.Watches.Copper, true, "Liste -> Menge")
	eq(data.Life.Equipped.Watch, "", "kaputte Uhr -> leer")
	eq(#data.Life.Equipped.Acc, 3, "max. 3 Accessoires, ohne Doppelte")
	local svc = serviceModule(nil, "LifestyleService")
	for _, entry in ipairs(Config.Decor.Items) do
		local comfort = svc.Comfort(entry.Key)
		truthy(comfort >= 1 and comfort <= 5, entry.Key .. ": Komfort " .. comfort)
	end
	eq(svc.Comfort("GibtEsNicht"), 0, "unbekannt = 0")
end

-- 10) PartSpec -> BasePart überträgt alle Eigenschaften
function Tests.InstantiateSpec()
	local spec = TowerModels.Shell(5, 12, "GlassBlue", "Gold")[1]
	local part = TowerModels.Instantiate(spec, CFrame.new(10, 0, 0), nil)
	truthy(part.Anchored, "verankert")
	eq(part.CanCollide, spec.Collide == true, "Kollision")
	truthy(math.abs(part.Size.X - spec.Size[1]) < 1e-3, "Größe")
	truthy(math.abs(part.Position.X - (10 + spec.Pos[1])) < 1e-3, "Position mit Ursprung")
	eq(part:GetAttribute("Tag"), spec.Tag, "Tag-Attribut")
	part:Destroy()
end

-- 11) Alle WP8-Texte in beiden Sprachen
function Tests.LangKeys()
	for _, key in ipairs({
		"tui.title",
		"tui.tab.overview",
		"tui.tab.floors",
		"tui.tab.facade",
		"tui.build",
		"tui.elevator.title",
		"tui.welcome.title",
		"tui.future.title",
		"life.title",
		"life.tab.watches",
		"life.notForSale",
		"life.noCredits",
		"life.accFull",
		"life.boughtWorn",
	}) do
		truthy(Lang.Has(key), "Lang-Schlüssel fehlt: " .. key)
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, "Text fehlt in einer Sprache: " .. key)
	end
end

return Tests
