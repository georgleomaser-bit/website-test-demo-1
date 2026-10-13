--!strict
-- =====================================================================
--  AKYTEX TYCOON – Uhren & Accessoires aus Parts (Shared/LifestyleModels)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C6.2 (LifestyleModels.Watch(key): Model),
--  §B12.2 (Uhren: 6–10 Parts, am Handgelenk geschweißt, Massless, CanCollide/CanQuery/CanTouch aus, Zeiger drehen
--  im Client-PreRender ≤ 60 Studs), §B12.3 (Accessoires aus Parts), §C14.3 (Asset-Plätze, 0 = Code-Rezept).
--
--  Rezepte sind deterministische PartSpec-Listen (reine Daten, Luau-CLI-testbar). Konvention:
--    Uhr:        Ursprung = Gehäuse-Mitte auf der Haut, Zifferblatt zeigt nach −Z, +Y = Richtung Hand (Unterarm-Achse).
--    Accessoire: Ursprung = Befestigungspunkt (Kopf vorn/oben, Brust vorn, Hand-Griff, Wurzel/Boden), vorn = −Z.
--  Die Zeiger sitzen auf Welds ("HourWeld"/"MinuteWeld", Part0 = Wurzel "Root" im Uhr-Ursprung) – der Client dreht nur Weld.C0
--  (Attribute HandZ/HandLen an den Zeiger-Teilen). Gebaute Modelle sind NICHT verankert und vollständig verschweißt
--  (PrimaryPart = "Root" bzw. "Mount"), damit LifestyleService sie mit EINEM Weld an die Figur hängen kann.
--
--  Öffentliche API:
--    LifestyleModels.Watch(key): Model            LifestyleModels.Accessory(key): Model
--    LifestyleModels.WatchSpecs(key): { PartSpec } LifestyleModels.AccessorySpecs(key): { PartSpec }
--    LifestyleModels.HandC0(z, len, angle): CFrame  (nur Roblox) Weld-C0 eines Zeigers für einen Winkel (Bogenmaß)
--    LifestyleModels.Kinds(): { string }           bekannte Accessoire-Rezepte
-- =====================================================================

local LifestyleModels = {}

type PartSpec = { [string]: any }
type Opts = { [string]: any }

local function loadModule(path: { string }, cliPath: string): any
	local here: any = script
	if typeof(here) == "Instance" then
		local node: any = here.Parent
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		if node and node:IsA("ModuleScript") then
			local ok, result = pcall(require, node :: any)
			return if ok then result else nil
		end
		return nil
	end
	local cliRequire: any = require
	local ok, result = pcall(cliRequire, cliPath)
	return if ok then result else nil
end

local TowerModels: any = loadModule({ "TowerModels" }, "./TowerModels")
local LifestyleConfig: any = loadModule({ "Config", "Lifestyle" }, "./Config/Lifestyle")

local DIAL_Z = -0.09 -- Zeiger-Ebene vor dem Zifferblatt
local HOUR_LEN, MINUTE_LEN = 0.17, 0.24

local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

local function p(
	list: { PartSpec },
	size: { number },
	pos: { number },
	color: string,
	material: string,
	opts: Opts?
): PartSpec
	local spec: PartSpec = {
		Size = { r3(size[1]), r3(size[2]), r3(size[3]) },
		Pos = { r3(pos[1]), r3(pos[2]), r3(pos[3]) },
		Color = color,
		Material = material,
		Shadow = false,
	}
	if opts then
		for key, value in pairs(opts) do
			spec[key] = value
		end
	end
	table.insert(list, spec)
	return spec
end

local FACING = { 0, 90, 0 } -- Zylinder-Achse X -> Z (Scheibe zeigt nach vorn)

local function entryOf(key: string): any
	local cfg = LifestyleConfig
	if type(cfg) ~= "table" or type(cfg.ByKey) ~= "table" then
		return nil
	end
	return cfg.ByKey[key]
end

-- ---------------------------------------------------------------------
-- UHREN (6–10 Parts)
-- ---------------------------------------------------------------------
function LifestyleModels.WatchSpecs(key: string): { PartSpec }
	local list: { PartSpec } = {}
	local entry = entryOf(key)
	local r = if entry and type(entry.Recipe) == "table" then entry.Recipe else nil
	if not r then
		return list
	end
	local round = r.Shape ~= "Square"
	-- unsichtbarer Wurzel-Punkt im Uhr-Ursprung (Primär-Teil, Zeiger-Welds beziehen sich darauf)
	p(list, { 0.05, 0.05, 0.05 }, { 0, 0, 0 }, r.Case, "SmoothPlastic", { Name = "Root", Transparency = 1 })
	-- Armband oben/unten auf dem Unterarm
	p(list, { 0.34, 0.42, 0.06 }, { 0, 0.42, 0.02 }, r.Strap, "Fabric", { Name = "StrapTop" })
	p(list, { 0.34, 0.42, 0.06 }, { 0, -0.42, 0.02 }, r.Strap, "Fabric", { Name = "StrapBottom" })
	-- Gehäuse (Ursprung)
	if round then
		p(
			list,
			{ 0.14, 0.62, 0.62 },
			{ 0, 0, -0.02 },
			r.Case,
			r.M or "Metal",
			{ Name = "Case", Shape = "Cylinder", Rot = FACING }
		)
	else
		p(list, { 0.58, 0.62, 0.14 }, { 0, 0, -0.02 }, r.Case, r.M or "Metal", { Name = "Case" })
	end
	if r.Bezel then
		p(list, { 0.03, 0.6, 0.6 }, { 0, 0, -0.095 }, r.Glow, "Metal", {
			Name = "Bezel",
			Shape = if round then "Cylinder" else "Block",
			Rot = if round then FACING else nil,
			Size = if round then { 0.03, 0.6, 0.6 } else { 0.56, 0.6, 0.03 },
		})
	end
	if round then
		p(
			list,
			{ 0.03, 0.5, 0.5 },
			{ 0, 0, -0.11 },
			r.Dial,
			"SmoothPlastic",
			{ Name = "Dial", Shape = "Cylinder", Rot = FACING }
		)
	else
		p(list, { 0.46, 0.5, 0.03 }, { 0, 0, -0.11 }, r.Dial, "SmoothPlastic", { Name = "Dial" })
	end
	-- Neon-Akzent (12-Uhr-Markierung) + Krone (Aufzug) rechts
	p(list, { 0.06, 0.06, 0.02 }, { 0, 0.2, -0.13 }, r.Glow, "Neon", { Name = "Marker" })
	p(list, { 0.1, 0.08, 0.08 }, { 0.33, 0, -0.03 }, r.Case, "Metal", { Name = "Crown" })
	-- Zeiger (Startstellung 12 Uhr; der Client dreht die Welds)
	p(list, { 0.05, HOUR_LEN, 0.02 }, { 0, HOUR_LEN / 2, DIAL_Z - 0.045 }, r.Hands, "Metal", {
		Name = "HourHand",
		Tag = "HourHand",
		Attr = { HandZ = DIAL_Z - 0.045, HandLen = HOUR_LEN },
	})
	p(list, { 0.035, MINUTE_LEN, 0.02 }, { 0, MINUTE_LEN / 2, DIAL_Z - 0.06 }, r.Hands, "Metal", {
		Name = "MinuteHand",
		Tag = "MinuteHand",
		Attr = { HandZ = DIAL_Z - 0.06, HandLen = MINUTE_LEN },
	})
	return list
end

-- ---------------------------------------------------------------------
-- ACCESSOIRES
-- ---------------------------------------------------------------------
type Builder = (list: { PartSpec }, r: { [string]: any }) -> ()
local A: { [string]: Builder } = {}

-- Sonnenbrille: Ursprung = Augenhöhe vor dem Gesicht
A.Sunglasses = function(list, r)
	p(list, { 1.15, 0.1, 0.08 }, { 0, 0.08, 0 }, r.B, "Metal", { Name = "Mount" })
	p(list, { 0.46, 0.3, 0.05 }, { -0.29, -0.06, -0.02 }, r.A, "Glass", { Transparency = 0.15, Reflectance = 0.4 })
	p(list, { 0.46, 0.3, 0.05 }, { 0.29, -0.06, -0.02 }, r.A, "Glass", { Transparency = 0.15, Reflectance = 0.4 })
	p(list, { 0.06, 0.06, 0.95 }, { -0.58, 0.06, 0.47 }, r.B, "Metal")
	p(list, { 0.06, 0.06, 0.95 }, { 0.58, 0.06, 0.47 }, r.B, "Metal")
	p(list, { 1.0, 0.03, 0.02 }, { 0, 0.14, -0.05 }, r.C, "Neon")
end

-- Krawattennadel: Ursprung = Brust vorn
A.TiePin = function(list, r)
	p(list, { 0.55, 0.08, 0.06 }, { 0, 0, 0 }, r.A, "Metal", { Name = "Mount" })
	p(list, { 0.14, 0.14, 0.14 }, { 0.2, 0, -0.04 }, r.C, "Neon", { Shape = "Ball" })
	p(list, { 0.08, 0.08, 0.04 }, { -0.22, 0, -0.03 }, r.B, "Metal")
end

-- Aktentasche: Ursprung = Griff in der Hand
A.Briefcase = function(list, r)
	p(list, { 0.5, 0.1, 0.12 }, { 0, 0, 0 }, r.C, "Metal", { Name = "Mount" })
	p(list, { 0.08, 0.3, 0.1 }, { -0.25, -0.15, 0 }, r.C, "Metal")
	p(list, { 0.08, 0.3, 0.1 }, { 0.25, -0.15, 0 }, r.C, "Metal")
	p(list, { 1.5, 1.05, 0.38 }, { 0, -0.82, 0 }, r.A, "Leather")
	p(list, { 1.52, 0.06, 0.4 }, { 0, -0.55, 0 }, r.B, "Metal")
	p(list, { 0.16, 0.12, 0.42 }, { -0.4, -0.5, 0 }, r.B, "Metal")
	p(list, { 0.16, 0.12, 0.42 }, { 0.4, -0.5, 0 }, r.B, "Metal")
end

-- Revers-Neon: Ursprung = Brust vorn links
A.Lapel = function(list, r)
	p(list, { 0.08, 0.9, 0.05 }, { 0, 0, 0 }, r.A, "Neon", { Name = "Mount", Rot = { 0, 0, -18 } })
	p(list, { 0.06, 0.5, 0.05 }, { 0.12, -0.55, 0 }, r.A, "Neon", { Rot = { 0, 0, 25 } })
	p(list, { 0.16, 0.16, 0.06 }, { -0.08, 0.38, -0.02 }, r.C, "Neon", { Shape = "Ball" })
end

-- Aura-Ring: Ursprung = Boden unter der Figur; zwei schwebende Ringe (Client dreht sie langsam)
A.Aura = function(list, r)
	p(
		list,
		{ 0.2, 0.6, 0.6 },
		{ 0, 0, 0 },
		r.A,
		"Neon",
		{ Name = "Mount", Shape = "Cylinder", Rot = { 0, 0, 90 }, Transparency = 1 }
	)
	p(list, { 0.12, 4.2, 4.2 }, { 0, 0.3, 0 }, r.A, "Neon", {
		Name = "RingLow",
		Shape = "Cylinder",
		Rot = { 0, 0, 90 },
		Transparency = 0.45,
		Tag = "Aura",
	})
	p(list, { 0.08, 3.4, 3.4 }, { 0, 1.6, 0 }, r.B, "Neon", {
		Name = "RingHigh",
		Shape = "Cylinder",
		Rot = { 0, 0, 82 },
		Transparency = 0.6,
		Tag = "Aura",
	})
end

-- Holo-Abzeichen: Ursprung = Brust vorn rechts
A.Badge = function(list, r)
	p(list, { 0.05, 0.5, 0.5 }, { 0, 0, 0 }, r.B, "Metal", { Name = "Mount", Shape = "Cylinder", Rot = FACING })
	p(list, { 0.03, 0.56, 0.56 }, { 0, 0, 0.01 }, r.A, "Neon", { Shape = "Cylinder", Rot = FACING, Transparency = 0.3 })
	p(list, { 0.05, 0.3, 0.03 }, { -0.06, 0, -0.04 }, r.C, "Neon", { Rot = { 0, 0, -20 } })
	p(list, { 0.05, 0.3, 0.03 }, { 0.06, 0, -0.04 }, r.C, "Neon", { Rot = { 0, 0, 20 } })
end

-- Community-Krone: Ursprung = Kopf oben
A.Crown = function(list, r)
	p(
		list,
		{ 0.3, 1.25, 1.25 },
		{ 0, 0.15, 0 },
		r.A,
		"Metal",
		{ Name = "Mount", Shape = "Cylinder", Rot = { 0, 0, 90 } }
	)
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2
		p(list, { 0.16, 0.42, 0.16 }, { math.cos(a) * 0.55, 0.5, math.sin(a) * 0.55 }, r.B, "Metal")
		if i % 2 == 1 then
			p(
				list,
				{ 0.14, 0.14, 0.14 },
				{ math.cos(a) * 0.55, 0.78, math.sin(a) * 0.55 },
				r.C,
				"Neon",
				{ Shape = "Ball" }
			)
		end
	end
end

function LifestyleModels.Kinds(): { string }
	local list: { string } = {}
	for kind in pairs(A) do
		table.insert(list, kind)
	end
	table.sort(list)
	return list
end

function LifestyleModels.AccessorySpecs(key: string): { PartSpec }
	local list: { PartSpec } = {}
	local entry = entryOf(key)
	local r = if entry and type(entry.Recipe) == "table" then entry.Recipe else nil
	if not r then
		return list
	end
	local builder = A[r.Kind]
	if builder then
		builder(list, r)
	end
	return list
end

-- ---------------------------------------------------------------------
-- ROBLOX: Modelle bauen (unverankert, verschweißt, Massless, ohne Kollision/Abfrage/Berührung)
-- ---------------------------------------------------------------------
function LifestyleModels.HandC0(z: number, len: number, angle: number): any
	return (CFrame :: any).new(0, 0, z) * (CFrame :: any).Angles(0, 0, -angle) * (CFrame :: any).new(0, len / 2, 0)
end

local function assemble(specs: { PartSpec }, name: string, primaryName: string): any
	local model = (Instance :: any).new("Model")
	model.Name = name
	local origin = (CFrame :: any).identity
	local primary: any = nil
	local parts: { any } = {}
	for _, spec in ipairs(specs) do
		if TowerModels then
			local part = TowerModels.Instantiate(spec, origin, model)
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			table.insert(parts, part)
			if part.Name == primaryName and primary == nil then
				primary = part
			end
		end
	end
	primary = primary or parts[1]
	if not primary then
		return model
	end
	model.PrimaryPart = primary
	for _, part in ipairs(parts) do
		if part ~= primary then
			local tag = part:GetAttribute("Tag")
			if tag == "HourHand" or tag == "MinuteHand" then
				local weld = (Instance :: any).new("Weld")
				weld.Name = if tag == "HourHand" then "HourWeld" else "MinuteWeld"
				weld.Part0 = primary
				weld.Part1 = part
				local z = part:GetAttribute("HandZ")
				local len = part:GetAttribute("HandLen")
				-- Root liegt im Uhr-Ursprung (ohne Drehung) -> C0 ist direkt die Zeiger-Lage im Uhr-Raum
				weld.C0 = primary.CFrame:ToObjectSpace(origin)
					* LifestyleModels.HandC0(
						if type(z) == "number" then z else DIAL_Z,
						if type(len) == "number" then len else HOUR_LEN,
						0
					)
				weld.Parent = part
			else
				local weld = (Instance :: any).new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	model.WorldPivot = origin
	return model
end

local function fromAsset(category: string, key: string, recipe: () -> any): any
	local entry = entryOf(key)
	local here: any = script
	if entry and entry.Asset and typeof(here) == "Instance" then
		local assetModule = here.Parent and here.Parent:FindFirstChild("AssetSlot")
		if assetModule then
			local ok, AssetSlot = pcall(require, assetModule :: any)
			if ok and type(AssetSlot) == "table" then
				local built = AssetSlot.Mesh(AssetSlot.KeyOf(category, key), entry.Asset, recipe)
				if built and built:IsA("Model") and built:GetAttribute("AssetSlot") == true then
					-- Mesh-Vorlage: unverankert, ohne Kollision, Primär-Teil setzen
					for _, d in ipairs(built:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored = false
							d.Massless = true
							d.CanCollide = false
							d.CanQuery = false
							d.CanTouch = false
							if built.PrimaryPart == nil then
								built.PrimaryPart = d
							end
						end
					end
				end
				return built
			end
		end
	end
	return recipe()
end

function LifestyleModels.Watch(key: string): any
	local model = fromAsset("Lifestyle", key, function(): any
		return assemble(LifestyleModels.WatchSpecs(key), "AkyWatch", "Root")
	end)
	model.Name = "AkyWatch"
	model:SetAttribute("AkyWatch", key)
	return model
end

function LifestyleModels.Accessory(key: string): any
	local model = fromAsset("Lifestyle", key, function(): any
		return assemble(LifestyleModels.AccessorySpecs(key), "AkyAcc", "Mount")
	end)
	model.Name = "AkyAcc_" .. key
	model:SetAttribute("AkyAccessory", key)
	return model
end

return LifestyleModels
