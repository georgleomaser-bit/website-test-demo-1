--!strict
-- =====================================================================
--  AKYTEX TYCOON – Deko-Rezepte (Shared/DecorModels)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C6.2 (DecorModels.Build(key): Model),
--  §B4.8 (60 Deko-Teile in 6 Sets + Saison-Set: Schreibtische mit Live-Mini-Monitor, Sofas, Pflanzen, Aquarium mit
--  getweenten Fischen, Skulpturen, Part-„Kunst“, Trophäen, Neon-Schilder aus ΛKYTEX-Strichen, Teppiche, Lampen mit
--  echten Lichtern im Budget), §C14.3 (Asset-Platz je Teil: MeshId ≠ 0 -> Mesh, sonst/Fehler -> Code-Rezept).
--
--  Rezepte sind deterministische PartSpec-Listen (Shared/TowerModels.PartSpec, reine Daten -> Luau-CLI-testbar):
--  Ursprung = Boden-Mitte des Teils, Vorderseite = lokal −Z, Grundfläche ≤ 5 × 5 Studs, Höhe ≤ 8,4 Studs (passt unter
--  jede Decke). Das Interior (TowerModels.Interior) dreht/verschiebt sie in die festen Deko-Plätze.
--  Gestaltung kommt aus Config.Decor[key].Recipe { Kind, A, B, C, M, S } – Kind wählt das Rezept, A/B/C die Farben,
--  M das Hauptmaterial, S die Skala.
--
--  Öffentliche API:
--    DecorModels.Build(key): Model                 Asset (falls gesetzt und geladen) oder Code-Rezept; Pivot = Ursprung
--    DecorModels.Specs(key): { PartSpec }          Rezept-Teile (gecacht – nur lesen!)
--    DecorModels.SpecsFor(recipe): { PartSpec }    Rezept aus einer Recipe-Tabelle (Boutique-Vorschau, Tests)
--    DecorModels.Kinds(): { string }               alle bekannten Rezept-Arten (Tests: jede Config-Art existiert)
--    DecorModels.Has(kind): boolean
--  Beim Laden registriert sich das Modul als Deko-Lieferant bei TowerModels (Deko im Interior).
-- =====================================================================

local DecorModels = {}

type PartSpec = { [string]: any }
type Recipe = { [string]: any }
type Opts = { [string]: any }

-- TowerModels / Config.Decor: in Roblox über script, in der Luau-CLI über relative Pfade
local function loadModule(name: string, cliPath: string): any
	local here: any = script
	if typeof(here) == "Instance" then
		local module = here.Parent and here.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module :: any)
			return if ok then result else nil
		end
		return nil
	end
	local cliRequire: any = require
	local ok, result = pcall(cliRequire, cliPath)
	return if ok then result else nil
end

local function loadDecorConfig(): any
	local here: any = script
	if typeof(here) == "Instance" then
		local config = here.Parent and here.Parent:FindFirstChild("Config")
		local module = config and config:FindFirstChild("Decor")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module :: any)
			return if ok then result else nil
		end
		return nil
	end
	local cliRequire: any = require
	local ok, result = pcall(cliRequire, "./Config/Decor")
	return if ok then result else nil
end

local TowerModels: any = loadModule("TowerModels", "./TowerModels")
local DecorConfig: any = loadDecorConfig()

local VERTICAL = { 0, 0, 90 }
local MAX_PARTS = 14 -- je Deko-Teil (3 Plätze × 14 + Raum + Personal bleibt ≤ 150)

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- Teil mit Skala s (Größe und Position werden skaliert)
local function p(
	list: { PartSpec },
	s: number,
	size: { number },
	pos: { number },
	color: string,
	material: string,
	opts: Opts?
): PartSpec
	local spec: PartSpec = {
		Size = { r3(math.max(0.05, size[1] * s)), r3(math.max(0.05, size[2] * s)), r3(math.max(0.05, size[3] * s)) },
		Pos = { r3(pos[1] * s), r3(pos[2] * s), r3(pos[3] * s) },
		Color = color,
		Material = material,
	}
	if opts then
		for key, value in pairs(opts) do
			spec[key] = value
		end
	end
	table.insert(list, spec)
	return spec
end

local function cyl(extra: Opts?): Opts
	local o: Opts = { Shape = "Cylinder", Rot = VERTICAL }
	if extra then
		for k, v in pairs(extra) do
			o[k] = v
		end
	end
	return o
end

local function ball(extra: Opts?): Opts
	local o: Opts = { Shape = "Ball" }
	if extra then
		for k, v in pairs(extra) do
			o[k] = v
		end
	end
	return o
end

local function light(range: number, brightness: number, color: string): Opts
	return { Light = { Range = range, Brightness = brightness, Color = color }, Shadow = false }
end

-- Hex-Farben mischen (für Rechen-Linien im Sand)
local function mix(a: string, b: string, t: number): string
	local function parse(hex: string): (number, number, number)
		return tonumber(string.sub(hex, 2, 3), 16) or 0,
			tonumber(string.sub(hex, 4, 5), 16) or 0,
			tonumber(string.sub(hex, 6, 7), 16) or 0
	end
	local ar, ag, ab = parse(a)
	local br, bg, bb = parse(b)
	local function c(x: number): number
		return math.clamp(math.floor(x + 0.5), 0, 255)
	end
	return string.format("#%02x%02x%02x", c(ar + (br - ar) * t), c(ag + (bg - ag) * t), c(ab + (bb - ab) * t))
end

-- ---------------------------------------------------------------------
-- REZEPTE (je ≤ 14 Parts; A = Hauptfarbe, B = Zweitfarbe, C = Akzent, M = Material, s = Skala)
-- ---------------------------------------------------------------------
type Builder = (list: { PartSpec }, r: Recipe, s: number) -> ()
local R: { [string]: Builder } = {}

R.Desk = function(list, r, s)
	p(
		list,
		s,
		{ 4.6, 0.3, 2.4 },
		{ 0, 2.6, 0 },
		r.A,
		r.M,
		{ Collide = true, Transparency = if r.M == "Glass" then 0.3 else 0 }
	)
	p(list, s, { 0.3, 2.45, 2.2 }, { -2.1, 1.25, 0 }, r.B, "Metal")
	p(list, s, { 0.3, 2.45, 2.2 }, { 2.1, 1.25, 0 }, r.B, "Metal")
	p(list, s, { 1.8, 1.1, 0.12 }, { 0, 3.45, 0.7 }, "#0b0f17", "SmoothPlastic", {
		Tag = "Monitor",
		Attr = { Monitor = "Chart", Face = "Front" },
	})
	p(list, s, { 1.9, 0.08, 0.1 }, { 0, 2.82, 0.62 }, r.C, "Neon", { Shadow = false })
	p(list, s, { 1.4, 0.06, 0.5 }, { 0, 2.78, -0.4 }, "#1f2937", "SmoothPlastic")
end

R.BeanBag = function(list, r, s)
	p(list, s, { 3, 1.8, 3 }, { 0, 0.9, 0 }, r.A, r.M, ball({ Collide = true }))
	p(list, s, { 2.4, 1.2, 2.4 }, { 0, 1.6, 0.5 }, r.A, r.M, ball())
	p(list, s, { 0.12, 2.9, 2.9 }, { 0, 0.15, 0 }, r.B, "Fabric", cyl())
end

R.Plant = function(list, r, s)
	p(list, s, { 1.6, 1.8, 1.8 }, { 0, 0.8, 0 }, r.B, r.M, cyl({ Collide = true }))
	p(list, s, { 2.6, 2.2, 2.6 }, { 0, 2.8, 0 }, r.A, "Grass", ball())
	p(list, s, { 1.8, 1.6, 1.8 }, { 0.8, 3.8, -0.3 }, r.C, "Grass", ball())
	p(list, s, { 1.6, 1.4, 1.6 }, { -0.7, 3.6, 0.4 }, r.A, "Grass", ball())
end

R.Whiteboard = function(list, r, s)
	p(list, s, { 4.4, 2.8, 0.15 }, { 0, 3.6, 0 }, r.A, r.M)
	p(list, s, { 4.6, 0.15, 0.3 }, { 0, 2.15, -0.05 }, r.B, "Metal")
	p(list, s, { 0.15, 2.2, 0.15 }, { -1.8, 1.1, 0.4 }, r.B, "Metal")
	p(list, s, { 0.15, 2.2, 0.15 }, { 1.8, 1.1, 0.4 }, r.B, "Metal")
	-- „Ideen“-Kurve aus drei Strichen (steigender Chart)
	p(list, s, { 1.2, 0.12, 0.05 }, { -1.1, 3.0, -0.1 }, r.C, "Neon", { Rot = { 0, 0, 18 }, Shadow = false })
	p(list, s, { 1.2, 0.12, 0.05 }, { 0, 3.5, -0.1 }, r.C, "Neon", { Rot = { 0, 0, 35 }, Shadow = false })
	p(list, s, { 1.2, 0.12, 0.05 }, { 1.1, 4.1, -0.1 }, r.C, "Neon", { Rot = { 0, 0, 25 }, Shadow = false })
end

R.NeonArrow = function(list, r, s)
	p(list, s, { 0.3, 3.2, 3.2 }, { 0, 0.15, 0 }, r.B, r.M, cyl())
	p(list, s, { 0.25, 3, 0.25 }, { 0, 1.8, 0.3 }, r.B, "Metal")
	p(list, s, { 2.6, 0.35, 0.35 }, { -0.5, 3.6, 0 }, r.C, "Neon", { Rot = { 0, 0, 30 }, Shadow = false })
	p(list, s, { 1.4, 0.35, 0.35 }, { 0.9, 4.2, 0 }, r.C, "Neon", { Rot = { 0, 0, -45 }, Shadow = false })
	p(list, s, { 1.4, 0.35, 0.35 }, { 0.75, 4.75, 0 }, r.C, "Neon", { Rot = { 0, 0, 45 }, Shadow = false })
end

-- Bulle (Mini auf Sockel bis Gold-Statue): Körper, Kopf, Hörner, Beine
R.Bull = function(list, r, s)
	p(list, s, { 3.2, 0.6, 2.2 }, { 0, 0.3, 0 }, r.B, "Marble", { Collide = true })
	p(list, s, { 2.8, 1.5, 1.4 }, { 0, 1.9, 0.2 }, r.A, r.M)
	p(list, s, { 1.1, 1.1, 1.2 }, { 0, 2.3, -1.2 }, r.A, r.M)
	p(list, s, { 0.25, 0.25, 0.9 }, { -0.5, 2.9, -1.3 }, r.C, "Metal", { Rot = { 0, 35, 25 } })
	p(list, s, { 0.25, 0.25, 0.9 }, { 0.5, 2.9, -1.3 }, r.C, "Metal", { Rot = { 0, -35, -25 } })
	for _, q in ipairs({ { -0.9, -0.4 }, { 0.9, -0.4 }, { -0.9, 0.8 }, { 0.9, 0.8 } }) do
		p(list, s, { 0.4, 1.0, 0.4 }, { q[1], 1.0, q[2] }, r.A, r.M)
	end
end

R.Counter = function(list, r, s)
	p(list, s, { 4.4, 3.2, 1.8 }, { 0, 1.6, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 4.6, 0.25, 2.1 }, { 0, 3.3, 0 }, "#f4f6fa", "Marble")
	p(list, s, { 4.4, 0.15, 0.1 }, { 0, 0.5, -0.92 }, r.C, "Neon", { Shadow = false })
	p(list, s, { 1.1, 1.4, 0.8 }, { -1.2, 4.1, 0.2 }, r.B, "Glass", cyl({ Transparency = 0.25 }))
	p(list, s, { 0.9, 1.2, 0.7 }, { 0.1, 4.0, 0.3 }, r.C, "Glass", cyl({ Transparency = 0.25 }))
	p(list, s, { 0.6, 0.6, 0.6 }, { 1.4, 3.75, 0 }, "#f59e0b", "SmoothPlastic", ball())
end

R.Chair = function(list, r, s)
	p(list, s, { 2, 0.5, 2 }, { 0, 1.7, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 2, 2.8, 0.45 }, { 0, 3.3, 0.85 }, r.A, r.M)
	p(list, s, { 1.2, 0.8, 0.5 }, { 0, 4.9, 0.85 }, r.B, r.M)
	p(list, s, { 0.25, 1.6, 0.25 }, { 0, 0.8, 0 }, r.B, "Metal", cyl())
	p(list, s, { 0.2, 1.8, 1.8 }, { 0, 0.1, 0 }, r.B, "Metal", cyl())
	p(list, s, { 2.1, 0.15, 0.1 }, { 0, 3.3, 0.6 }, r.C, "Neon", { Shadow = false })
end

R.Art = function(list, r, s)
	p(list, s, { 3.4, 4.2, 0.2 }, { 0, 4.0, 0.2 }, "#1f2937", "Metal")
	p(list, s, { 3, 3.8, 0.1 }, { 0, 4.0, 0.05 }, r.A, r.M)
	p(list, s, { 1.4, 1.4, 0.08 }, { 0.4, 4.6, -0.02 }, r.B, "Neon", ball({ Shadow = false }))
	p(list, s, { 0.6, 2.2, 0.08 }, { -0.5, 3.6, -0.02 }, r.C, "SmoothPlastic", { Rot = { 0, 0, -30 } })
	p(list, s, { 1.4, 0.4, 0.4 }, { 0, 1.0, 0.6 }, "#2a3342", "Metal")
end

R.Rug = function(list, r, s)
	p(list, s, { 5, 0.08, 3.6 }, { 0, 0.14, 0 }, r.A, r.M)
	p(list, s, { 4.2, 0.1, 2.8 }, { 0, 0.16, 0 }, r.B, r.M)
	p(list, s, { 3.4, 0.12, 0.25 }, { 0, 0.18, 0 }, r.C, r.M)
	p(list, s, { 0.25, 0.12, 2 }, { 0, 0.18, 0 }, r.C, r.M)
end

R.Sofa = function(list, r, s)
	p(list, s, { 4.6, 1.3, 2.4 }, { 0, 0.9, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 4.6, 2.0, 0.7 }, { 0, 1.9, 0.9 }, r.A, r.M, { Collide = true })
	p(list, s, { 0.7, 1.8, 2.4 }, { -2.0, 1.3, 0 }, r.B, r.M)
	p(list, s, { 0.7, 1.8, 2.4 }, { 2.0, 1.3, 0 }, r.B, r.M)
	p(list, s, { 1.2, 0.9, 0.5 }, { -1.1, 2.1, 0.45 }, r.C, "Fabric", { Rot = { -15, 0, 0 } })
	p(list, s, { 4.6, 0.3, 2.2 }, { 0, 0.15, 0 }, "#1a1410", "Wood")
end

R.Bookshelf = function(list, r, s)
	p(list, s, { 4.2, 6.4, 1.2 }, { 0, 3.2, 0 }, r.A, r.M, { Collide = true })
	for i = 1, 3 do
		p(list, s, { 3.6, 1.2, 0.3 }, { 0, 0.9 + i * 1.6, -0.5 }, if i == 2 then r.C else r.B, "SmoothPlastic")
	end
	p(list, s, { 0.8, 0.8, 0.8 }, { 1.2, 6.0, -0.2 }, "#c8a165", "Metal", ball())
end

R.Tree = function(list, r, s)
	p(list, s, { 1.8, 1.4, 1.8 }, { 0, 0.7, 0 }, r.C, "Metal", cyl({ Collide = true }))
	p(list, s, { 4.2, 0.4, 0.4 }, { 0, 3.4, 0 }, r.B, r.M, cyl())
	p(list, s, { 2.8, 2.4, 2.8 }, { 0, 5.2, 0 }, r.A, "Grass", ball())
	p(list, s, { 2.0, 1.8, 2.0 }, { 0.9, 6.1, 0.2 }, r.A, "Grass", ball())
	p(list, s, { 1.8, 1.6, 1.8 }, { -0.8, 5.9, -0.4 }, r.A, "Grass", ball())
end

R.Globe = function(list, r, s)
	p(list, s, { 0.3, 2.2, 2.2 }, { 0, 0.15, 0 }, r.B, r.M, cyl({ Collide = true }))
	p(list, s, { 2.6, 0.25, 0.25 }, { 0, 1.5, 0 }, r.B, r.M, cyl())
	p(list, s, { 0.2, 3.2, 3.2 }, { 0, 4.0, 0 }, r.B, r.M, { Shape = "Cylinder", Rot = { 0, 90, 23 } })
	p(list, s, { 2.8, 2.8, 2.8 }, { 0, 4.0, 0 }, r.A, "SmoothPlastic", ball({ Group = "Globe", Anim = "Spin" }))
	p(list, s, { 1.2, 0.9, 0.6 }, { 0.5, 4.4, -1.1 }, r.C, "Grass", ball({ Group = "Globe", Anim = "Spin" }))
end

R.Clock = function(list, r, s)
	p(list, s, { 1.8, 7, 1.2 }, { 0, 3.5, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 0.15, 1.5, 1.5 }, { 0, 5.9, -0.62 }, r.B, "SmoothPlastic", { Shape = "Cylinder", Rot = { 0, 90, 0 } })
	p(list, s, { 0.08, 0.6, 0.08 }, { 0, 6.1, -0.72 }, r.C, "Metal")
	p(list, s, { 0.45, 0.08, 0.08 }, { 0.18, 5.9, -0.72 }, r.C, "Metal")
	p(
		list,
		s,
		{ 0.6, 0.6, 0.1 },
		{ 0, 2.6, -0.62 },
		r.C,
		"Metal",
		{ Shape = "Cylinder", Rot = { 0, 90, 0 }, Anim = "Swing", Group = "Pendulum" }
	)
	p(list, s, { 1.4, 2.6, 0.08 }, { 0, 3.2, -0.6 }, "#cfe3f7", "Glass", { Transparency = 0.5 })
end

R.Table = function(list, r, s)
	p(list, s, { 4.6, 0.3, 2.6 }, { 0, 2.6, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 0.6, 2.45, 0.6 }, { -1.6, 1.25, 0 }, r.B, "Metal", cyl())
	p(list, s, { 0.6, 2.45, 0.6 }, { 1.6, 1.25, 0 }, r.B, "Metal", cyl())
	p(list, s, { 4.6, 0.06, 0.12 }, { 0, 2.78, 0 }, r.C, "Metal")
	p(list, s, { 0.7, 0.8, 0.7 }, { 1.2, 3.1, 0.4 }, "#e6ecf5", "Ceramic", cyl())
end

R.Lamp = function(list, r, s)
	p(list, s, { 0.3, 1.6, 1.6 }, { 0, 0.15, 0 }, r.A, r.M, cyl({ Collide = true }))
	p(list, s, { 5.2, 0.2, 0.2 }, { 0, 2.8, 0 }, r.A, r.M, cyl())
	p(list, s, { 1.4, 1.8, 1.8 }, { 0, 5.7, 0 }, r.B, "Fabric", cyl({ Transparency = 0.15 }))
	local o = light(14, 1.2, r.C)
	o.Shape = "Ball"
	o.Tag = "Light"
	p(list, s, { 0.6, 0.6, 0.6 }, { 0, 5.4, 0 }, r.C, "Neon", o)
end

R.Trophy = function(list, r, s)
	p(list, s, { 1.8, 1.2, 1.8 }, { 0, 0.6, 0 }, r.B, "Marble", { Collide = true })
	p(list, s, { 1.4, 0.4, 1.4 }, { 0, 1.4, 0 }, r.A, r.M)
	p(list, s, { 1.2, 0.35, 0.35 }, { 0, 2.2, 0 }, r.A, r.M, cyl())
	p(list, s, { 1.8, 1.8, 1.8 }, { 0, 3.5, 0 }, r.A, r.M, cyl({ Transparency = if r.M == "Glass" then 0.15 else 0 }))
	p(list, s, { 0.25, 1.0, 1.0 }, { -1.05, 3.6, 0 }, r.A, r.M, { Shape = "Cylinder", Rot = { 0, 90, 0 } })
	p(list, s, { 0.25, 1.0, 1.0 }, { 1.05, 3.6, 0 }, r.A, r.M, { Shape = "Cylinder", Rot = { 0, 90, 0 } })
	p(list, s, { 0.6, 0.6, 0.6 }, { 0, 4.7, 0 }, r.C, "Neon", ball({ Shadow = false }))
end

R.EggChair = function(list, r, s)
	p(list, s, { 0.3, 2.2, 2.2 }, { 0, 0.15, 0 }, r.B, "Metal", cyl({ Collide = true }))
	p(list, s, { 1.4, 0.3, 0.3 }, { 0, 0.9, 0 }, r.B, "Metal", cyl())
	p(list, s, { 3, 3.6, 3 }, { 0, 3.2, 0.3 }, r.A, r.M, ball())
	p(list, s, { 2.2, 2.4, 1.0 }, { 0, 3.0, -0.9 }, r.C, "Fabric", ball())
end

R.Sculpture = function(list, r, s)
	p(list, s, { 1.8, 2.2, 1.8 }, { 0, 1.1, 0 }, r.B, "Marble", { Collide = true })
	p(list, s, { 1.2, 1.2, 1.2 }, { 0, 2.9, 0 }, r.A, r.M, { Rot = { 45, 0, 45 } })
	p(list, s, { 0.9, 0.9, 0.9 }, { 0.3, 4.0, 0.1 }, r.A, r.M, ball())
	p(list, s, { 0.3, 2.4, 0.3 }, { -0.2, 4.1, 0 }, r.A, r.M, { Rot = { 0, 0, 25 } })
	p(
		list,
		s,
		{ 0.15, 2.0, 2.0 },
		{ 0, 4.3, 0 },
		r.C,
		"Neon",
		{ Shape = "Cylinder", Rot = { 0, 30, 70 }, Shadow = false }
	)
end

-- Aquarium: Glasbecken, Wasser, Sockel, Deckel-Licht, Pflanzen, drei Fische (Client lässt sie schwimmen)
R.Aquarium = function(list, r, s)
	p(list, s, { 4.4, 2.6, 2 }, { 0, 1.3, 0 }, r.B, "Metal", { Collide = true })
	p(list, s, { 4.4, 2.8, 2 }, { 0, 4.0, 0 }, "#cfe3f7", "Glass", { Transparency = 0.7, Collide = true })
	p(list, s, { 4.2, 2.4, 1.8 }, { 0, 3.9, 0 }, r.A, "Glass", { Transparency = 0.55 })
	p(list, s, { 4.4, 0.2, 2 }, { 0, 5.5, 0 }, r.B, "Metal")
	p(list, s, { 4.2, 0.1, 0.2 }, { 0, 5.38, -0.85 }, "#e6f0ff", "Neon", { Shadow = false })
	p(list, s, { 0.6, 1.4, 0.6 }, { -1.4, 3.3, 0.3 }, "#2f9e5b", "Grass", { Rot = { 0, 0, 8 } })
	p(list, s, { 0.5, 1.0, 0.5 }, { 1.5, 3.1, 0.4 }, "#2f9e5b", "Grass", { Rot = { 0, 0, -10 } })
	for i = 1, 3 do
		p(
			list,
			s,
			{ 0.55, 0.32, 0.22 },
			{ -1 + (i - 1) * 0.9, 3.4 + i * 0.35, -0.2 + (i % 2) * 0.4 },
			r.C,
			"SmoothPlastic",
			{
				Tag = "Fish",
				Group = "Fish" .. i,
				Anim = "Fish",
				Shadow = false,
			}
		)
	end
end

R.ArcLamp = function(list, r, s)
	p(list, s, { 1.6, 0.4, 1.6 }, { -1.6, 0.2, 0 }, r.B, "Marble", { Collide = true })
	p(list, s, { 0.2, 5.4, 0.2 }, { -1.6, 2.9, 0 }, r.A, r.M, { Rot = { 0, 0, -12 } })
	p(list, s, { 0.2, 3.4, 0.2 }, { -0.2, 6.2, 0 }, r.A, r.M, { Rot = { 0, 0, -65 } })
	p(list, s, { 1.6, 1.0, 1.6 }, { 1.2, 6.4, 0 }, r.A, r.M, ball())
	local o = light(14, 1.2, r.C)
	o.Shape = "Ball"
	o.Tag = "Light"
	p(list, s, { 0.6, 0.6, 0.6 }, { 1.2, 5.9, 0 }, r.C, "Neon", o)
end

R.LowTable = function(list, r, s)
	p(
		list,
		s,
		{ 4, 0.3, 2.4 },
		{ 0, 1.4, 0 },
		r.A,
		r.M,
		{ Collide = true, Transparency = if r.M == "Glass" then 0.3 else 0 }
	)
	p(list, s, { 3.4, 1.25, 1.8 }, { 0, 0.62, 0 }, r.B, "Metal", { Transparency = 0.4 })
	p(list, s, { 0.5, 0.7, 0.5 }, { -1.1, 1.9, 0 }, r.C, "Ceramic", cyl())
	p(list, s, { 1.2, 0.1, 0.8 }, { 0.8, 1.6, 0.2 }, "#e6ecf5", "SmoothPlastic")
end

R.Prism = function(list, r, s)
	p(list, s, { 1.6, 1.8, 1.6 }, { 0, 0.9, 0 }, "#1f2937", "Marble", { Collide = true })
	p(list, s, { 2.2, 3.4, 2.2 }, { 0, 3.6, 0 }, r.A, r.M, { Kind = "Wedge", Transparency = 0.25, Reflectance = 0.3 })
	p(list, s, { 2.2, 3.4, 2.2 }, { 0, 3.6, 0 }, r.C, r.M, { Kind = "Wedge", Rot = { 0, 180, 0 }, Transparency = 0.45 })
	p(list, s, { 0.15, 4, 0.15 }, { 0, 3.6, -1.2 }, r.B, "Neon", { Rot = { 0, 0, 20 }, Shadow = false })
end

R.Screen = function(list, r, s)
	p(list, s, { 0.3, 2.4, 2.4 }, { 0, 0.15, 0 }, r.B, "Metal", cyl({ Collide = true }))
	p(list, s, { 0.3, 3.6, 0.3 }, { 0, 2.0, 0.3 }, r.B, "Metal")
	p(list, s, { 4.6, 2.8, 0.3 }, { 0, 4.8, 0.3 }, r.B, "Metal")
	p(list, s, { 4.3, 2.5, 0.1 }, { 0, 4.8, 0.1 }, r.A, r.M, {
		Tag = "Monitor",
		Attr = { Monitor = "Chart", Face = "Front" },
	})
	p(list, s, { 4.6, 0.12, 0.12 }, { 0, 3.35, 0.15 }, r.C, "Neon", { Shadow = false })
end

R.Bamboo = function(list, r, s)
	p(list, s, { 2.2, 2.6, 2.2 }, { 0, 1.3, 0 }, r.B, r.M, { Transparency = 0.45, Collide = true })
	for i = 1, 4 do
		local x = (i - 2.5) * 0.45
		p(list, s, { 6.4 - i * 0.4, 0.22, 0.22 }, { x, 3.4 - i * 0.2, (i % 2) * 0.3 - 0.15 }, r.A, "Wood", cyl())
	end
	p(list, s, { 1.8, 1.2, 1.8 }, { 0, 6.4, 0 }, r.C, "Grass", ball())
end

-- ΛKYTEX-Neonschild: Λ aus zwei Strichen + Ring nach logo.svg (Code, kein Upload)
R.LambdaSign = function(list, r, s)
	p(list, s, { 3.6, 3.6, 0.2 }, { 0, 4.4, 0.25 }, r.B, r.M)
	p(
		list,
		s,
		{ 0.25, 3.4, 3.4 },
		{ 0, 4.4, 0.1 },
		r.C,
		"Neon",
		{ Shape = "Cylinder", Rot = { 0, 90, 0 }, Transparency = 0.55, Shadow = false }
	)
	p(list, s, { 0.35, 2.6, 0.2 }, { -0.5, 4.3, -0.05 }, r.A, "Neon", { Rot = { 0, 0, -20 }, Shadow = false })
	p(list, s, { 0.35, 2.6, 0.2 }, { 0.5, 4.3, -0.05 }, r.A, "Neon", { Rot = { 0, 0, 20 }, Shadow = false })
	p(list, s, { 0.3, 2.6, 0.3 }, { 0, 1.3, 0.3 }, r.B, "Metal")
	p(list, s, { 0.3, 2, 2 }, { 0, 0.15, 0.3 }, r.B, "Metal", cyl({ Collide = true }))
end

R.HoloGlobe = function(list, r, s)
	p(list, s, { 0.6, 2.4, 2.4 }, { 0, 0.3, 0 }, r.B, r.M, cyl({ Collide = true }))
	p(list, s, { 0.2, 2.6, 2.6 }, { 0, 0.7, 0 }, r.A, "Neon", cyl({ Shadow = false }))
	p(
		list,
		s,
		{ 3, 3, 3 },
		{ 0, 3.4, 0 },
		r.A,
		"Neon",
		ball({ Transparency = 0.6, Group = "Holo", Anim = "Spin", Shadow = false })
	)
	p(list, s, { 0.15, 3.8, 3.8 }, { 0, 3.4, 0 }, r.C, "Neon", {
		Shape = "Cylinder",
		Rot = { 0, 0, 70 },
		Transparency = 0.3,
		Group = "Holo",
		Anim = "Spin",
		Shadow = false,
	})
end

R.PodChair = function(list, r, s)
	p(list, s, { 3, 0.8, 3 }, { 0, 0.4, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 3, 1.0, 2.6 }, { 0, 1.3, -0.1 }, r.B, "Fabric")
	p(list, s, { 3, 3.2, 1.0 }, { 0, 2.6, 1.1 }, r.A, r.M, { Kind = "Wedge", Rot = { 0, 180, 0 } })
	p(list, s, { 3.1, 0.12, 0.12 }, { 0, 0.82, -1.5 }, r.C, "Neon", { Shadow = false })
	p(list, s, { 0.12, 3, 0.12 }, { -1.5, 2.4, 1.0 }, r.C, "Neon", { Shadow = false })
end

R.Totem = function(list, r, s)
	p(list, s, { 2, 0.6, 2 }, { 0, 0.3, 0 }, r.B, r.M, { Collide = true })
	p(list, s, { 1.4, 6.4, 1.4 }, { 0, 3.8, 0 }, r.A, r.M)
	p(list, s, { 1.2, 5.6, 0.1 }, { 0, 3.8, -0.72 }, "#0b0f17", "SmoothPlastic", {
		Tag = "Monitor",
		Attr = { Monitor = "Chart", Face = "Front" },
	})
	p(list, s, { 1.5, 0.15, 1.5 }, { 0, 7.05, 0 }, r.C, "Neon", { Shadow = false })
	p(list, s, { 1.5, 0.15, 1.5 }, { 0, 0.65, 0 }, r.C, "Neon", { Shadow = false })
end

R.NeonTree = function(list, r, s)
	p(list, s, { 1.6, 0.8, 1.6 }, { 0, 0.4, 0 }, r.B, r.M, { Collide = true })
	p(list, s, { 4.4, 0.3, 0.3 }, { 0, 3.0, 0 }, r.B, r.M, cyl())
	for i = 1, 4 do
		local a = (i - 1) * 90
		p(list, s, { 0.18, 2.2, 0.18 }, { 0, 4.8, 0 }, if i % 2 == 0 then r.C else r.A, "Neon", {
			Rot = { 0, a, 40 },
			Shadow = false,
		})
	end
	p(list, s, { 2.4, 2.4, 2.4 }, { 0, 5.6, 0 }, r.A, "Neon", ball({ Transparency = 0.55, Shadow = false }))
end

R.RoboDog = function(list, r, s)
	p(list, s, { 1.6, 1.0, 2.6 }, { 0, 1.6, 0 }, r.A, r.M, { Group = "Dog", Anim = "Bob" })
	p(list, s, { 1.1, 1.0, 1.1 }, { 0, 2.3, -1.5 }, r.A, r.M, { Group = "Dog", Anim = "Bob" })
	p(list, s, { 0.9, 0.18, 0.1 }, { 0, 2.4, -2.07 }, r.C, "Neon", { Group = "Dog", Anim = "Bob", Shadow = false })
	for _, q in ipairs({ { -0.6, -0.9 }, { 0.6, -0.9 }, { -0.6, 0.9 }, { 0.6, 0.9 } }) do
		p(list, s, { 0.3, 1.2, 0.3 }, { q[1], 0.6, q[2] }, r.B, "Metal")
	end
	p(
		list,
		s,
		{ 0.2, 0.2, 1.0 },
		{ 0, 2.2, 1.6 },
		r.C,
		"Neon",
		{ Rot = { 30, 0, 0 }, Group = "Dog", Anim = "Bob", Shadow = false }
	)
end

R.LightCube = function(list, r, s)
	p(list, s, { 1.8, 0.8, 1.8 }, { 0, 0.4, 0 }, r.B, "Metal", { Collide = true })
	local o = light(12, 1.0, r.C)
	o.Transparency = 0.35
	o.Rot = { 0, 45, 0 }
	o.Group = "Cube"
	o.Anim = "Spin"
	o.Tag = "Light"
	p(list, s, { 2.4, 2.4, 2.4 }, { 0, 2.6, 0 }, r.A, r.M, o)
	p(
		list,
		s,
		{ 1.2, 1.2, 1.2 },
		{ 0, 2.6, 0 },
		r.C,
		"Neon",
		{ Rot = { 45, 45, 0 }, Group = "Cube", Anim = "Spin", Shadow = false }
	)
end

R.Console = function(list, r, s)
	p(list, s, { 3, 5.6, 2.4 }, { 0, 2.8, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 2.4, 1.8, 0.1 }, { 0, 4.3, -1.22 }, "#0b0f17", "SmoothPlastic", {
		Tag = "Monitor",
		Attr = { Monitor = "Chart", Face = "Front" },
	})
	p(list, s, { 3, 0.8, 1.2 }, { 0, 2.8, -1.6 }, r.A, r.M, { Kind = "Wedge", Rot = { 0, 180, 0 } })
	p(list, s, { 0.4, 0.4, 0.4 }, { -0.6, 3.25, -1.7 }, r.C, "Neon", ball({ Shadow = false }))
	p(list, s, { 0.4, 0.4, 0.4 }, { 0.3, 3.25, -1.7 }, r.B, "Neon", ball({ Shadow = false }))
	p(list, s, { 3.1, 0.15, 2.5 }, { 0, 5.65, 0 }, r.B, "Neon", { Shadow = false })
end

R.Chandelier = function(list, r, s)
	p(list, s, { 0.15, 1.6, 0.15 }, { 0, 7.8, 0 }, r.A, r.M)
	p(list, s, { 0.4, 3.2, 3.2 }, { 0, 6.9, 0 }, r.A, r.M, cyl())
	local o = light(16, 1.3, r.C)
	o.Tag = "Light"
	o.Shape = "Ball"
	p(list, s, { 1.0, 1.0, 1.0 }, { 0, 6.4, 0 }, r.C, "Neon", o)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		p(list, s, { 0.35, 0.8, 0.35 }, { math.cos(a) * 1.4, 6.3, math.sin(a) * 1.4 }, r.B, "Glass", {
			Transparency = 0.2,
			Shadow = false,
		})
	end
	p(list, s, { 2.2, 0.3, 0.3 }, { 0, 0.15, 0 }, r.A, r.M, cyl())
end

R.Piano = function(list, r, s)
	p(list, s, { 4.2, 1.2, 4.6 }, { 0, 2.6, 0.3 }, r.A, r.M, { Collide = true })
	p(list, s, { 4.2, 1.6, 2.4 }, { 0, 3.4, 1.4 }, r.A, r.M, { Kind = "Wedge", Rot = { 0, 180, 0 } })
	p(list, s, { 3.8, 0.2, 0.8 }, { 0, 2.3, -2.2 }, r.B, "SmoothPlastic")
	p(list, s, { 3.8, 0.22, 0.25 }, { 0, 2.42, -2.0 }, "#0b0f17", "SmoothPlastic")
	for _, x in ipairs({ -1.7, 1.7 }) do
		p(list, s, { 0.4, 2.0, 0.4 }, { x, 1.0, -1.6 }, r.A, r.M, cyl())
	end
	p(list, s, { 0.4, 2.0, 0.4 }, { 0, 1.0, 2.2 }, r.A, r.M, cyl())
	p(list, s, { 4.25, 0.1, 0.1 }, { 0, 3.2, -1.95 }, r.C, "Metal")
end

R.Vase = function(list, r, s)
	p(list, s, { 1.4, 1.2, 1.4 }, { 0, 0.6, 0 }, "#1a1410", "Marble", { Collide = true })
	p(list, s, { 1.8, 1.8, 1.8 }, { 0, 2.0, 0 }, r.A, r.M, ball())
	p(list, s, { 1.6, 0.8, 0.8 }, { 0, 3.4, 0 }, r.A, r.M, cyl())
	p(list, s, { 0.15, 1.9, 1.9 }, { 0, 2.0, 0 }, r.B, "Metal", cyl())
	p(list, s, { 0.8, 0.8, 0.8 }, { 0.3, 4.6, 0 }, r.C, "Grass", ball())
	p(list, s, { 0.7, 0.7, 0.7 }, { -0.35, 4.4, 0.2 }, r.C, "Grass", ball())
end

R.Fountain = function(list, r, s)
	p(list, s, { 0.8, 4.4, 4.4 }, { 0, 0.4, 0 }, r.B, r.M, cyl({ Collide = true }))
	p(list, s, { 0.3, 3.8, 3.8 }, { 0, 0.85, 0 }, r.C, "Glass", cyl({ Transparency = 0.35, Reflectance = 0.2 }))
	p(list, s, { 2.8, 0.6, 0.6 }, { 0, 2.2, 0 }, r.A, r.M, cyl())
	p(list, s, { 0.3, 2.2, 2.2 }, { 0, 3.6, 0 }, r.A, r.M, cyl())
	p(list, s, { 1.4, 0.4, 0.4 }, { 0, 4.4, 0 }, r.C, "Neon", cyl({ Transparency = 0.4, Shadow = false }))
	p(list, s, { 0.9, 0.9, 0.9 }, { 0, 5.2, 0 }, r.A, r.M, ball())
end

R.Bonsai = function(list, r, s)
	p(list, s, { 2.6, 0.8, 1.8 }, { 0, 1.8, 0 }, r.C, r.M, { Collide = true })
	p(list, s, { 2.2, 1.4, 1.6 }, { 0, 0.7, 0 }, "#1f2937", "Wood")
	p(list, s, { 0.35, 1.6, 0.35 }, { 0, 3.0, 0 }, r.B, "Wood", { Rot = { 0, 0, 20 } })
	p(list, s, { 0.3, 1.2, 0.3 }, { 0.4, 3.6, 0 }, r.B, "Wood", { Rot = { 0, 0, -50 } })
	p(list, s, { 1.6, 0.8, 1.2 }, { -0.5, 3.9, 0 }, r.A, "Grass", ball())
	p(list, s, { 1.3, 0.7, 1.0 }, { 0.9, 4.1, 0.1 }, r.A, "Grass", ball())
end

R.SandGarden = function(list, r, s)
	p(list, s, { 4.6, 0.6, 3.4 }, { 0, 0.3, 0 }, "#3a2418", "Wood", { Collide = true })
	p(list, s, { 4.2, 0.2, 3.0 }, { 0, 0.62, 0 }, r.A, r.M)
	p(list, s, { 1.0, 0.8, 0.9 }, { -1.1, 0.9, 0.3 }, r.B, "Slate", ball())
	p(list, s, { 0.7, 0.6, 0.6 }, { 1.2, 0.85, -0.5 }, r.B, "Slate", ball())
	for i = 1, 3 do
		p(list, s, { 3.8, 0.04, 0.08 }, { 0, 0.73, -1.1 + i * 0.5 }, mix(r.A, "#ffffff", 0.3), "Sand")
	end
	p(list, s, { 0.5, 0.5, 0.5 }, { 1.5, 0.95, 1.0 }, r.C, "Grass", ball())
end

R.Lantern = function(list, r, s)
	p(list, s, { 1.8, 0.6, 1.8 }, { 0, 0.3, 0 }, r.B, r.M, { Collide = true })
	p(list, s, { 2.4, 0.6, 0.6 }, { 0, 1.8, 0 }, r.A, r.M, cyl())
	p(list, s, { 1.6, 1.4, 1.6 }, { 0, 3.6, 0 }, r.A, r.M)
	local o = light(12, 1.0, r.C)
	o.Tag = "Light"
	p(list, s, { 1.0, 1.0, 1.7 }, { 0, 3.6, 0 }, r.C, "Neon", o)
	p(list, s, { 2.4, 0.5, 2.4 }, { 0, 4.55, 0 }, r.B, r.M)
	p(list, s, { 0.8, 0.6, 0.8 }, { 0, 5.1, 0 }, r.B, r.M, ball())
end

R.WaterBowl = function(list, r, s)
	p(list, s, { 1.6, 1.6, 1.6 }, { 0, 0.8, 0 }, r.A, r.M, cyl({ Collide = true }))
	p(list, s, { 0.8, 3.8, 3.8 }, { 0, 1.9, 0 }, r.A, r.M, cyl())
	p(list, s, { 0.2, 3.4, 3.4 }, { 0, 2.32, 0 }, r.B, "Glass", cyl({ Transparency = 0.25, Reflectance = 0.3 }))
	p(list, s, { 0.6, 0.12, 0.6 }, { 0.8, 2.45, 0.4 }, r.C, "SmoothPlastic", cyl())
	p(list, s, { 0.5, 0.12, 0.5 }, { -0.6, 2.45, -0.5 }, r.C, "SmoothPlastic", cyl())
end

R.BlossomTree = function(list, r, s)
	p(list, s, { 2.2, 1.0, 2.2 }, { 0, 0.5, 0 }, "#5b5f66", "Slate", { Collide = true })
	p(list, s, { 4.6, 0.45, 0.45 }, { 0, 3.2, 0 }, r.B, r.M, cyl({ Rot = { 0, 0, 80 } }))
	p(list, s, { 0.3, 2.2, 0.3 }, { 0.6, 5.2, 0 }, r.B, r.M, { Rot = { 0, 0, -40 } })
	p(list, s, { 3, 2.0, 3 }, { -0.3, 6.0, 0 }, r.A, "Grass", ball())
	p(list, s, { 2.2, 1.6, 2.2 }, { 1.2, 6.5, 0.3 }, r.C, "Grass", ball())
	p(list, s, { 1.8, 1.4, 1.8 }, { -1.4, 5.6, -0.4 }, r.A, "Grass", ball())
	p(list, s, { 3.2, 0.06, 3.2 }, { 0, 1.03, 0 }, r.C, "SmoothPlastic", cyl())
end

R.Gong = function(list, r, s)
	p(list, s, { 0.5, 6, 0.5 }, { -2, 3, 0 }, r.B, "Wood", { Collide = true })
	p(list, s, { 0.5, 6, 0.5 }, { 2, 3, 0 }, r.B, "Wood", { Collide = true })
	p(list, s, { 4.8, 0.5, 0.5 }, { 0, 6.1, 0 }, r.B, "Wood")
	p(
		list,
		s,
		{ 0.2, 3.4, 3.4 },
		{ 0, 3.8, 0 },
		r.A,
		r.M,
		{ Shape = "Cylinder", Rot = { 0, 90, 0 }, Group = "Gong", Anim = "Swing" }
	)
	p(
		list,
		s,
		{ 0.25, 1.2, 1.2 },
		{ 0, 3.8, -0.15 },
		r.C,
		"Metal",
		{ Shape = "Cylinder", Rot = { 0, 90, 0 }, Group = "Gong", Anim = "Swing" }
	)
	p(list, s, { 4.4, 0.4, 1.4 }, { 0, 0.2, 0 }, r.B, "Wood")
end

R.Pond = function(list, r, s)
	p(list, s, { 0.6, 4.6, 4.6 }, { 0, 0.3, 0 }, r.A, r.M, cyl({ Collide = true }))
	p(list, s, { 0.2, 4.0, 4.0 }, { 0, 0.62, 0 }, r.B, "Glass", cyl({ Transparency = 0.2, Reflectance = 0.35 }))
	for i = 1, 3 do
		p(
			list,
			s,
			{ 0.6, 0.2, 0.25 },
			{ -0.8 + i * 0.5, 0.7, -0.6 + (i % 2) * 1.0 },
			if i == 2 then "#f4f6fa" else r.C,
			"SmoothPlastic",
			{
				Tag = "Fish",
				Group = "Koi" .. i,
				Anim = "Fish",
				Shadow = false,
			}
		)
	end
	p(list, s, { 0.9, 0.7, 0.8 }, { 1.6, 0.9, 1.1 }, "#8a8f98", "Slate", ball())
	p(list, s, { 0.6, 0.06, 0.6 }, { -1.1, 0.74, 0.9 }, "#3f8f3a", "SmoothPlastic", cyl())
end

R.Screenwall = function(list, r, s)
	for i = 1, 3 do
		local x = (i - 2) * 1.6
		p(
			list,
			s,
			{ 1.5, 5.6, 0.2 },
			{ x, 3.0, 0 },
			r.A,
			r.M,
			{ Rot = { 0, if i == 2 then 0 else (i - 2) * -25, 0 }, Collide = true }
		)
		p(
			list,
			s,
			{ 1.5, 0.15, 0.25 },
			{ x, 5.9, 0 },
			r.B,
			"Wood",
			{ Rot = { 0, if i == 2 then 0 else (i - 2) * -25, 0 } }
		)
	end
	p(list, s, { 0.6, 0.6, 0.6 }, { 0, 6.2, 0 }, r.C, "Grass", ball())
end

R.CalmPod = function(list, r, s)
	p(list, s, { 3.6, 0.8, 4.4 }, { 0, 0.4, 0 }, r.B, "SmoothPlastic", { Collide = true })
	p(list, s, { 3.4, 3.4, 4.2 }, { 0, 2.0, 0 }, r.A, r.M, ball())
	p(list, s, { 2.4, 1.8, 0.3 }, { 0, 2.1, -1.95 }, "#121824", "Glass", { Transparency = 0.3 })
	local o = light(10, 0.8, r.C)
	o.Tag = "Light"
	p(list, s, { 3.5, 0.15, 4.3 }, { 0, 0.85, 0 }, r.C, "Neon", o)
end

R.SkylineModel = function(list, r, s)
	p(list, s, { 4.2, 2.6, 2.6 }, { 0, 1.3, 0 }, r.A, "Marble", { Collide = true })
	p(list, s, { 4.4, 0.2, 2.8 }, { 0, 2.7, 0 }, r.B, "Neon", { Shadow = false, Transparency = 0.2 })
	local heights = { 1.6, 2.8, 4.2, 2.2, 3.4 }
	for i, h in ipairs(heights) do
		p(
			list,
			s,
			{ 0.6, h, 0.6 },
			{ (i - 3) * 0.8, 2.8 + h / 2, (i % 2) * 0.5 - 0.25 },
			if i == 3 then r.C else r.B,
			r.M,
			{
				Transparency = 0.25,
				Reflectance = 0.25,
			}
		)
	end
end

R.Bench = function(list, r, s)
	p(list, s, { 4.6, 0.4, 1.6 }, { 0, 1.6, 0 }, r.A, r.M, { Collide = true })
	p(list, s, { 4.6, 1.6, 0.3 }, { 0, 2.6, 0.65 }, r.A, r.M)
	p(list, s, { 0.3, 1.4, 1.4 }, { -2.0, 0.7, 0 }, r.A, r.M)
	p(list, s, { 0.3, 1.4, 1.4 }, { 2.0, 0.7, 0 }, r.A, r.M)
	p(list, s, { 4.6, 0.12, 0.12 }, { 0, 1.38, -0.8 }, r.B, "Neon", { Shadow = false })
	p(list, s, { 4.6, 0.12, 0.12 }, { 0, 3.42, 0.65 }, r.C, "Neon", { Shadow = false })
end

R.Palm = function(list, r, s)
	p(list, s, { 2, 1, 2 }, { 0, 0.5, 0 }, r.B, "Metal", { Collide = true })
	p(list, s, { 5.2, 0.35, 0.35 }, { 0, 3.6, 0 }, r.B, r.M, cyl())
	for i = 1, 5 do
		p(list, s, { 0.25, 2.6, 0.6 }, { 0, 6.4, 0 }, if i % 2 == 0 then r.C else r.A, "Neon", {
			Rot = { 0, (i - 1) * 72, 62 },
			Shadow = false,
		})
	end
end

R.OrbitLamp = function(list, r, s)
	p(list, s, { 0.3, 1.8, 1.8 }, { 0, 0.15, 0 }, r.B, r.M, cyl({ Collide = true }))
	p(list, s, { 3.6, 0.2, 0.2 }, { 0, 1.9, 0 }, r.B, r.M, cyl())
	local o = light(12, 1.1, r.C)
	o.Shape = "Ball"
	o.Tag = "Light"
	p(list, s, { 1.4, 1.4, 1.4 }, { 0, 4.4, 0 }, r.C, "Neon", o)
	p(list, s, { 0.15, 3.0, 3.0 }, { 0, 4.4, 0 }, r.A, "Neon", {
		Shape = "Cylinder",
		Rot = { 0, 0, 60 },
		Group = "Orbit",
		Anim = "Spin",
		Transparency = 0.2,
		Shadow = false,
	})
	p(
		list,
		s,
		{ 0.5, 0.5, 0.5 },
		{ 1.5, 4.4, 0 },
		r.A,
		"Neon",
		ball({ Group = "Orbit", Anim = "Spin", Shadow = false })
	)
end

R.Blimp = function(list, r, s)
	p(list, s, { 0.3, 1.6, 1.6 }, { 0, 0.15, 0 }, r.B, "Metal", cyl({ Collide = true }))
	p(list, s, { 0.15, 3.6, 0.15 }, { 0, 2.0, 0 }, r.B, "Metal")
	p(list, s, { 1.6, 1.6, 4.4 }, { 0, 4.6, 0 }, r.A, r.M, ball({ Group = "Blimp", Anim = "Bob" }))
	p(list, s, { 0.6, 0.5, 1.2 }, { 0, 3.7, 0 }, r.B, r.M, { Group = "Blimp", Anim = "Bob" })
	p(list, s, { 0.12, 0.9, 0.8 }, { 0, 4.9, 2.0 }, r.C, "Neon", { Group = "Blimp", Anim = "Bob", Shadow = false })
	p(list, s, { 1.65, 0.15, 2.6 }, { 0, 4.6, 0 }, r.C, "Neon", { Group = "Blimp", Anim = "Bob", Shadow = false })
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
local cache: { [string]: { PartSpec } } = {}
local cacheCount = 0
local MAX_CACHE = 128

local function entryOf(key: string): any
	local cfg = DecorConfig
	if type(cfg) ~= "table" or type(cfg.ByKey) ~= "table" then
		return nil
	end
	return cfg.ByKey[key]
end

function DecorModels.Has(kind: string): boolean
	return R[kind] ~= nil
end

function DecorModels.Kinds(): { string }
	local list: { string } = {}
	for kind in pairs(R) do
		table.insert(list, kind)
	end
	table.sort(list)
	return list
end

function DecorModels.SpecsFor(recipe: Recipe): { PartSpec }
	local list: { PartSpec } = {}
	if type(recipe) ~= "table" or type(recipe.Kind) ~= "string" then
		return list
	end
	local builder = R[recipe.Kind] or R.Plant
	local scale = if type(recipe.S) == "number" and recipe.S == recipe.S then math.clamp(recipe.S, 0.3, 2) else 1
	local r: Recipe = {
		A = if type(recipe.A) == "string" then recipe.A else "#4f8cff",
		B = if type(recipe.B) == "string" then recipe.B else "#1a2130",
		C = if type(recipe.C) == "string" then recipe.C else "#e6ecf5",
		M = if type(recipe.M) == "string" then recipe.M else "SmoothPlastic",
	}
	builder(list, r, scale)
	while #list > MAX_PARTS do
		table.remove(list)
	end
	return list
end

function DecorModels.Specs(key: string): { PartSpec }
	local cached = cache[key]
	if cached then
		return cached
	end
	local entry = entryOf(key)
	if not entry then
		return {}
	end
	local list = DecorModels.SpecsFor(entry.Recipe)
	if cacheCount < MAX_CACHE then
		cache[key] = list
		cacheCount += 1
	end
	return list
end

-- Model mit Pivot im Ursprung (Asset-Platz -> MeshPart-Vorlage; 0/Fehler -> Code-Rezept)
function DecorModels.Build(key: string): any
	local entry = entryOf(key)
	local function recipe(): any
		local model = (Instance :: any).new("Model")
		model.Name = "Decor_" .. tostring(key)
		local origin = (CFrame :: any).identity
		for _, spec in ipairs(DecorModels.Specs(key)) do
			if TowerModels then
				TowerModels.Instantiate(spec, origin, model)
			end
		end
		model.WorldPivot = origin
		return model
	end
	local slot = if entry then entry.Asset else nil
	local here: any = script
	if slot and typeof(here) == "Instance" then
		local assetModule = here.Parent and here.Parent:FindFirstChild("AssetSlot")
		if assetModule then
			local ok, AssetSlot = pcall(require, assetModule :: any)
			if ok and type(AssetSlot) == "table" then
				local built = AssetSlot.Mesh(AssetSlot.KeyOf("Decor", key), slot, recipe)
				return built
			end
		end
	end
	return recipe()
end

-- Deko-Lieferant für TowerModels.Interior
if TowerModels and type(TowerModels.SetDecorProvider) == "function" then
	TowerModels.SetDecorProvider(DecorModels.Specs)
end

return DecorModels
