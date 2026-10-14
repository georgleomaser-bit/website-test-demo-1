-- =====================================================================
--  AKYTEX TYCOON – Welt-Events auf dem Client (Client/Modules/EventsClient)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §B10 (Welt-Events, Glocken-Moment, Sky-Show, Bär/Bulle,
--  Bullen-Parade, Geldregen, Samstags-Show), §C7.2 (Hooks World:*), §C7.5 (EventsClient.Active), §C8 (Remote "World"),
--  §C9 (EventPickup), §C16 (Budgets), §0 Regel 2 (keine Animationen: prozedurale CFrame-Bewegung im EINEN PreRender-Loop).
--
--  Aufgaben:
--    * Pickups pro Spieler (World:Pickups / World:PickupGone): Bündel, Pakete, Kugeln, Münzen, Quiz-Felder als LOKALE
--      Teile (kein Wegschnappen, nichts repliziert); automatisches Einsammeln in Reichweite (Request "EventPickup" {Id},
--      Server prüft Abstand ≤ 12, Fenster, Eigentum); "+CR"-Schild, CR-Puls im HUD.
--    * Welt-Darsteller aus State "Event" + World:Event: Geldtransporter (Ring), Liefer-Drohnen, Bau-Boom-Kräne,
--      Roboter-CEO-Hologramm mit Quartalszahlen + Quiz, Bär (stapft auf die Plaza, verbeugt sich bei Erfolg), goldener
--      Bulle (Ring), Bullen-Parade (5 Bullen + „Danke, Name!“), Top-10-Hologramm am Bilanz-Sonntag, Glocken-Zone.
--    * Golden Hour: WorldLook.SetOverride("Golden") solange sie läuft (nur wenn wir es gesetzt haben).
--    * Wartungs-Banner (workspace-Attribut "AT_Maintenance", Live-Ops-Notschalter) und Bär-Fortschritt (World:Bear).
--  Alle Modelle über AssetSlot (Config.Events.Assets, 0 = Code-Rezept aus Parts); Teile gepoolt, Bewegung per
--  workspace:BulkMoveTo. Frame(dt) kommt aus dem einen PreRender-Loop (FRAME_MODULES) und treibt auch EffectsEvent.Step.
--  HUD-Pillen (Welt-Event, ADMIN-ABUSE) zeigt Hud selbst aus State.Event (ein Besitzer je Anzeige, REUSE §7 #39).
--
--  Öffentliche API (§C7.5):
--    EventsClient.Active(): { Types.EventState }
--    EventsClient.Init(ctx) · EventsClient.Start() · EventsClient.Frame(dt)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local EventsClient = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme
local AssetSlot: any = nil

type Visual = { Model: Instance, Parts: { BasePart }, Offsets: { CFrame } }
type TokenVis = {
	Id: number,
	Kind: string,
	Pos: Vector3,
	Until: number,
	Born: number,
	Ready: number, -- ab dann einsammelbar (Fall/Anflug vorbei)
	Visual: Visual,
	Base: string, -- Pool-Schlüssel
	Requested: number,
	Q: number,
	O: number,
	Gui: BillboardGui?,
	Phase: number,
}
type Actor = {
	Key: string,
	Kind: string,
	Started: number,
	Until: number,
	Data: { [string]: any },
	Visuals: { Visual },
	Extra: { [string]: any },
	Leaving: number?,
}
type Route = { Points: { Vector3 }, Cum: { number }, Length: number }

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(250, 204, 21)
local BROWN = Color3.fromRGB(139, 90, 43)
local BROWN_LIGHT = Color3.fromRGB(210, 166, 121)
local CARDBOARD = Color3.fromRGB(176, 138, 90)
local DARK = Color3.fromRGB(11, 15, 23)
local METAL = Color3.fromRGB(31, 41, 55)
local COSMIC = Color3.fromRGB(124, 156, 255)

local AUTO_RANGE = 9 -- Client sammelt ab hier automatisch (Server erlaubt 12)
local QUIZ_RANGE = 3.6 -- Antwort-Felder: drauf stehen
local REQUEST_GAP = 1.0 -- je Token höchstens 1 Anfrage pro Sekunde
local REQUESTS_PER_SECOND = 8 -- Server-Limit EventPickup 10/s
local COLLECT_CHECK = 0.1
local BELL_CHECK = 0.25
local POOL_MAX = 30
local FLOAT_TEXTS = 6
local COIN_FALL = 40
local DRONE_HEIGHT = 70
local BEAR_WALK = 7 -- Sekunden: Bär stapft vom Rand zur Mitte
local PARADE_GAP = 16 -- Studs zwischen den Parade-Bullen
local MAX_ACTORS = 24

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
local folder: Folder? = nil
local gui: ScreenGui? = nil
local tokens: { [number]: TokenVis } = {}
local pools: { [string]: { Visual } } = {}
local actors: { [string]: Actor } = {}
local routeCache: { [string]: Route } = {}
local requestTimes: { number } = {}
local floatPool: { { Gui: BillboardGui, Label: TextLabel, Anchor: Part, Until: number } } = {}
local collectAcc = 0
local bellAcc = 0
local goldenSet = false
local photoHidden = false
local bearHave, bearGoal = 0, 0
local profileCache: { [number]: { At: number, Profile: any } } = {}
local pressRequested: { [string]: boolean } = {}

-- UI-Elemente
local bearBar: Frame? = nil
local bearFill: Frame? = nil
local bearLabel: TextLabel? = nil
local banner: Frame? = nil
local bannerLabel: TextLabel? = nil
local bellRing: Part? = nil
local bellGui: BillboardGui? = nil
local bellLabel: TextLabel? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function lang(): string
	if ctx and type(ctx.Lang_) == "function" then
		return ctx.Lang_()
	end
	return "en"
end

local function module(name: string): any
	local modules = ctx and ctx.Modules
	return if type(modules) == "table" then modules[name] else nil
end

local function tryModule(name: string, fnName: string, ...: any): (boolean, any)
	local m = module(name)
	local fn = if type(m) == "table" then m[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function now(): number
	local clock = ctx and ctx.Clock
	if clock and type(clock.Now) == "function" then
		local ok, value = pcall(clock.Now)
		if ok and type(value) == "number" then
			return value
		end
	end
	return workspace:GetServerTimeNow()
end

local function num(value: any, default: number): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		then value
		else default
end

local function eventsCfg(): any
	local config = ctx and ctx.Config
	return (config and config.Events) or {}
end

local function sfx(role: string, pos: Vector3?, opts: any?)
	tryModule("Sfx", "Play", role, pos, opts)
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function plazaCenter(): Vector3
	local city = ctx and ctx.Config and ctx.Config.City
	local zones = city and city.Zones
	local plaza = zones and zones.Plaza
	if plaza and typeof(plaza.Center) == "Vector3" then
		return plaza.Center
	end
	return Vector3.zero
end

local function attrVector(name: string): Vector3?
	local value = workspace:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else nil
end

-- ---------------------------------------------------------------------
-- BAUSTEINE (lokale Teile, nie kollidierend, nie abfragbar)
-- ---------------------------------------------------------------------
local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "Mesh" then
			(p :: any)[key] = value
		end
	end
	if props.Mesh == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

-- Echte Lichter an den Darstellern (Future-Licht), nur im Licht-Budget der Grafikstufe (Config.Quality.Lights)
local function lightBudget(): number
	local ok, value = tryModule("Quality", "Budget", "Lights")
	return if ok and type(value) == "number" then value else 16
end

local function addLight(parent: BasePart, className: string, minBudget: number, props: { [string]: any })
	if lightBudget() < minBudget then
		return
	end
	local light = Instance.new(className)
	light.Name = "AT_EventLight"
	for key, value in pairs(props) do
		(light :: any)[key] = value
	end
	(light :: any).Shadows = false -- bewegte Darsteller: keine Schatten-Kosten
	light.Parent = parent
end

local function newModel(name: string, parts: { Part }): Model
	local m = Instance.new("Model")
	m.Name = name
	for _, p in ipairs(parts) do
		p.Parent = m
	end
	m.WorldPivot = CFrame.identity
	return m
end

-- Hybrid-Asset (Config.Events.Assets[key]) oder Code-Rezept; alles lokal, verankert, ohne Kollision
local function build(key: string, recipe: () -> Instance): Instance
	local cfg = eventsCfg()
	local slot = cfg.Assets and cfg.Assets[key] or nil
	local inst: Instance
	if AssetSlot and type(AssetSlot.Mesh) == "function" then
		local ok, result = pcall(AssetSlot.Mesh, "Events." .. key, slot, recipe)
		inst = if ok and typeof(result) == "Instance" then result else recipe()
	else
		inst = recipe()
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
	end
	return inst
end

local function toVisual(inst: Instance): Visual
	local pivot = if inst:IsA("Model")
		then inst:GetPivot()
		elseif inst:IsA("BasePart") then inst.CFrame
		else CFrame.identity
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local list = inst:GetDescendants()
	if inst:IsA("BasePart") then
		table.insert(list, 1, inst)
	end
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
		end
	end
	inst.Parent = folder
	return { Model = inst, Parts = parts, Offsets = offsets }
end

local bulkParts: { BasePart } = {}
local bulkFrames: { CFrame } = {}

local function queueMove(v: Visual, cf: CFrame)
	for i, p in ipairs(v.Parts) do
		table.insert(bulkParts, p)
		table.insert(bulkFrames, cf * v.Offsets[i])
	end
end

local function flushMoves()
	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(bulkParts)
		table.clear(bulkFrames)
	end
end

local function setVisible(v: Visual, on: boolean)
	local target = if on then nil else 1
	for _, p in ipairs(v.Parts) do
		local orig = p:GetAttribute("AT_T")
		if orig == nil then
			p:SetAttribute("AT_T", p.Transparency)
			orig = p.Transparency
		end
		p.Transparency = if target then target else orig
	end
end

local function destroyVisual(v: Visual)
	v.Model:Destroy()
end

-- ---------------------------------------------------------------------
-- REZEPTE (Code-Modelle aus Parts, Pivot = Boden-Mitte, vorne = −Z)
-- ---------------------------------------------------------------------
local RECIPES: { [string]: () -> Instance } = {}

RECIPES.Truck = function(): Instance
	-- Scheinwerfer vorne (−Z) mit echten SpotLights, grünes Dach-Signal mit kleinem Leuchtschein
	local lamps: { Part } = {}
	for _, side in ipairs({ -1, 1 }) do
		local lamp = part({
			Name = "Headlight",
			Size = Vector3.new(1.3, 0.6, 0.2),
			CFrame = CFrame.new(side * 2.5, 2.7, -10.08),
			Color = Color3.fromRGB(240, 246, 255),
			Material = Enum.Material.Neon,
		})
		addLight(lamp, "SpotLight", 16, {
			Face = Enum.NormalId.Front,
			Range = 38,
			Angle = 55,
			Brightness = 2.6,
			Color = Color3.fromRGB(235, 242, 255),
		})
		table.insert(lamps, lamp)
	end
	local model = newModel("AT_Truck", {
		part({
			Size = Vector3.new(7, 6, 15),
			CFrame = CFrame.new(0, 4, 2.5),
			Color = METAL,
			Material = Enum.Material.Metal,
		}),
		part({
			Size = Vector3.new(7.1, 0.45, 15.1),
			CFrame = CFrame.new(0, 4.4, 2.5),
			Color = Theme.Accent,
			Material = Enum.Material.Neon,
		}),
		part({
			Size = Vector3.new(7, 5, 5),
			CFrame = CFrame.new(0, 3.5, -7.5),
			Color = Theme.Surface,
			Material = Enum.Material.Metal,
		}),
		part({
			Size = Vector3.new(6.4, 2, 0.3),
			CFrame = CFrame.new(0, 4.6, -10.05),
			Color = Theme.Accent,
			Material = Enum.Material.Glass,
			Transparency = 0.35,
		}),
		part({
			Name = "Beacon",
			Size = Vector3.new(2.4, 0.4, 1),
			CFrame = CFrame.new(0, 6.2, -7.5),
			Color = Theme.Up,
			Material = Enum.Material.Neon,
		}),
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 3, 3),
			CFrame = CFrame.new(-3.6, 1.5, -6),
			Color = DARK,
		}),
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 3, 3),
			CFrame = CFrame.new(3.6, 1.5, -6),
			Color = DARK,
		}),
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 3, 3),
			CFrame = CFrame.new(-3.6, 1.5, 6),
			Color = DARK,
		}),
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 3, 3),
			CFrame = CFrame.new(3.6, 1.5, 6),
			Color = DARK,
		}),
	})
	for _, lamp in ipairs(lamps) do
		lamp.Parent = model
	end
	local beacon = model:FindFirstChild("Beacon")
	if beacon and beacon:IsA("BasePart") then
		addLight(beacon, "PointLight", 32, { Range = 12, Brightness = 1.4, Color = Theme.Up })
	end
	return model
end

RECIPES.Drone = function(): Instance
	local parts = {
		part({
			Size = Vector3.new(2.2, 0.7, 2.2),
			CFrame = CFrame.new(),
			Color = Theme.Surface2,
			Material = Enum.Material.Metal,
		}),
		part({ Size = Vector3.new(4.8, 0.25, 0.35), CFrame = CFrame.Angles(0, math.rad(45), 0), Color = METAL }),
		part({ Size = Vector3.new(4.8, 0.25, 0.35), CFrame = CFrame.Angles(0, math.rad(-45), 0), Color = METAL }),
		part({
			Size = Vector3.new(0.5, 0.2, 0.5),
			CFrame = CFrame.new(0, -0.45, 0),
			Color = Theme.Up,
			Material = Enum.Material.Neon,
		}),
		part({ Name = "Cargo", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(0, -1.5, 0), Color = CARDBOARD }),
	}
	for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		table.insert(
			parts,
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.15, 2.2, 2.2),
				CFrame = CFrame.new(corner[1] * 1.7, 0.35, corner[2] * 1.7) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Theme.Accent,
				Material = Enum.Material.Neon,
				Transparency = 0.45,
			})
		)
	end
	return newModel("AT_Drone", parts)
end

local function bullRecipe(): Instance
	local function gold(props: { [string]: any }): Part
		props.Color = props.Color or GOLD
		props.Material = props.Material or Enum.Material.Metal
		props.Reflectance = props.Reflectance or 0.25
		return part(props)
	end
	local body = gold({ Size = Vector3.new(5, 5, 9), CFrame = CFrame.new(0, 4.6, 0), Mesh = "Sphere" })
	addLight(body, "PointLight", 32, { Range = 18, Brightness = 1.6, Color = GOLD }) -- goldener Schein auf dem Asphalt
	return newModel("AT_Bull", {
		body,
		gold({ Size = Vector3.new(3, 3, 3.5), CFrame = CFrame.new(0, 5.6, -5), Mesh = "Sphere" }),
		gold({ Size = Vector3.new(2.2, 1.6, 1.4), CFrame = CFrame.new(0, 4.9, -6.6), Mesh = "Sphere" }),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 0.5, 0.5),
			CFrame = CFrame.new(-1.7, 7, -5.2) * CFrame.Angles(0, 0, -0.6),
			Color = Color3.fromRGB(255, 244, 220),
		}),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 0.5, 0.5),
			CFrame = CFrame.new(1.7, 7, -5.2) * CFrame.Angles(0, 0, 0.6),
			Color = Color3.fromRGB(255, 244, 220),
		}),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 1, 1),
			CFrame = CFrame.new(-1.5, 1.5, -2.8) * CFrame.Angles(0, 0, math.pi / 2),
		}),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 1, 1),
			CFrame = CFrame.new(1.5, 1.5, -2.8) * CFrame.Angles(0, 0, math.pi / 2),
		}),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 1, 1),
			CFrame = CFrame.new(-1.5, 1.5, 2.8) * CFrame.Angles(0, 0, math.pi / 2),
		}),
		gold({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 1, 1),
			CFrame = CFrame.new(1.5, 1.5, 2.8) * CFrame.Angles(0, 0, math.pi / 2),
		}),
		gold({ Size = Vector3.new(0.3, 0.3, 2.4), CFrame = CFrame.new(0, 5.2, 5) * CFrame.Angles(-0.6, 0, 0) }),
	})
end
RECIPES.Bull = bullRecipe

RECIPES.Bear = function(): Instance
	local function fur(props: { [string]: any }): Part
		props.Color = props.Color or BROWN
		props.Mesh = props.Mesh or "Sphere"
		return part(props)
	end
	return newModel("AT_Bear", {
		fur({ Size = Vector3.new(8, 9, 7), CFrame = CFrame.new(0, 6.2, 0) }),
		fur({ Size = Vector3.new(5, 6, 1.6), CFrame = CFrame.new(0, 5.6, -3.1), Color = BROWN_LIGHT }),
		fur({ Size = Vector3.new(6, 5.5, 5.5), CFrame = CFrame.new(0, 12.2, 0) }),
		fur({ Size = Vector3.new(2, 2, 1.2), CFrame = CFrame.new(-2.2, 14.6, 0) }),
		fur({ Size = Vector3.new(2, 2, 1.2), CFrame = CFrame.new(2.2, 14.6, 0) }),
		fur({ Size = Vector3.new(2.6, 2, 2), CFrame = CFrame.new(0, 11.4, -2.7), Color = BROWN_LIGHT }),
		fur({ Size = Vector3.new(1, 0.7, 0.7), CFrame = CFrame.new(0, 11.9, -3.7), Color = DARK }),
		fur({ Size = Vector3.new(0.7, 0.7, 0.4), CFrame = CFrame.new(-1.2, 13, -2.6), Color = DARK }),
		fur({ Size = Vector3.new(0.7, 0.7, 0.4), CFrame = CFrame.new(1.2, 13, -2.6), Color = DARK }),
		fur({ Size = Vector3.new(2.2, 5, 2.2), CFrame = CFrame.new(-4.6, 6.6, -0.6) }),
		fur({ Size = Vector3.new(2.2, 5, 2.2), CFrame = CFrame.new(4.6, 6.6, -0.6) }),
		fur({ Size = Vector3.new(2.6, 3, 3), CFrame = CFrame.new(-2.2, 1.5, -0.4) }),
		fur({ Size = Vector3.new(2.6, 3, 3), CFrame = CFrame.new(2.2, 1.5, -0.4) }),
	})
end

RECIPES.Coin = function(): Instance
	return newModel("AT_Coin", {
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 2.6, 2.6),
			CFrame = CFrame.new(),
			Color = Theme.Up,
			Material = Enum.Material.Neon,
		}),
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 1.5, 1.5),
			CFrame = CFrame.new(),
			Color = Color3.fromRGB(220, 252, 231),
			Material = Enum.Material.Metal,
		}),
	})
end

RECIPES.Bundle = function(): Instance
	return newModel("AT_Bundle", {
		part({ Size = Vector3.new(2.4, 0.9, 1.3), CFrame = CFrame.new(), Color = Color3.fromRGB(22, 163, 74) }),
		part({
			Size = Vector3.new(0.5, 0.95, 1.35),
			CFrame = CFrame.new(),
			Color = Theme.Text,
			Material = Enum.Material.Neon,
		}),
	})
end

RECIPES.Package = function(): Instance
	return newModel("AT_Package", {
		part({ Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(), Color = CARDBOARD }),
		part({
			Size = Vector3.new(2.45, 0.3, 2.45),
			CFrame = CFrame.new(),
			Color = Theme.Accent,
			Material = Enum.Material.Neon,
		}),
	})
end

RECIPES.Orb = function(): Instance
	return newModel("AT_Orb", {
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = CFrame.new(),
			Color = COSMIC,
			Material = Enum.Material.Neon,
		}),
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.2, 3.2, 3.2),
			CFrame = CFrame.new(),
			Color = COSMIC,
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
		}),
	})
end

RECIPES.Pad = function(): Instance
	return newModel("AT_QuizPad", {
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 6, 6),
			CFrame = CFrame.Angles(0, 0, math.pi / 2),
			Color = Theme.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
		}),
	})
end

RECIPES.Hologram = function(): Instance
	local holo = { Material = Enum.Material.Neon, Color = Theme.Accent, Transparency = 0.35 }
	local function h(props: { [string]: any }): Part
		for k, v in pairs(holo) do
			if props[k] == nil then
				props[k] = v
			end
		end
		return part(props)
	end
	return newModel("AT_PressCEO", {
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 6.5, 6.5),
			CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = METAL,
			Material = Enum.Material.Metal,
		}),
		h({
			Shape = Enum.PartType.Cylinder,
			Name = "Ring",
			Size = Vector3.new(0.3, 5, 5),
			CFrame = CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		}),
		h({ Size = Vector3.new(2.8, 4.2, 2.2), CFrame = CFrame.new(0, 5.4, 0), Mesh = "Sphere" }),
		(function(): Part
			local head =
				h({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), CFrame = CFrame.new(0, 8.9, 0) })
			addLight(head, "PointLight", 16, { Range = 20, Brightness = 1.3, Color = Theme.Accent })
			return head
		end)(),
		h({ Size = Vector3.new(0.5, 0.5, 0.2), CFrame = CFrame.new(-0.6, 9.1, -1.55), Color = WHITE, Transparency = 0 }),
		h({ Size = Vector3.new(0.5, 0.5, 0.2), CFrame = CFrame.new(0.6, 9.1, -1.55), Color = WHITE, Transparency = 0 }),
	})
end

RECIPES.Crane = function(): Instance
	local yellow = Theme.Warn
	return newModel("AT_EventCrane", {
		part({
			Size = Vector3.new(1.4, 60, 1.4),
			CFrame = CFrame.new(0, 30, 0),
			Color = yellow,
			Material = Enum.Material.Metal,
		}),
		part({
			Size = Vector3.new(26, 1.2, 1.4),
			CFrame = CFrame.new(7, 60, 0),
			Color = yellow,
			Material = Enum.Material.Metal,
		}),
		part({
			Size = Vector3.new(3, 2.4, 2.4),
			CFrame = CFrame.new(-5.5, 59, 0),
			Color = METAL,
			Material = Enum.Material.Metal,
		}),
		part({ Size = Vector3.new(0.15, 12, 0.15), CFrame = CFrame.new(17, 54, 0), Color = DARK }),
		(function(): Part
			local hook = part({
				Size = Vector3.new(1.2, 1.2, 1.2),
				CFrame = CFrame.new(17, 47.5, 0),
				Color = Theme.Down,
				Material = Enum.Material.Neon,
			})
			addLight(hook, "PointLight", 32, { Range = 10, Brightness = 1.2, Color = Theme.Down })
			return hook
		end)(),
	})
end

-- ---------------------------------------------------------------------
-- ROUTEN (identisch zum Server: Config.City.RoutePoints)
-- ---------------------------------------------------------------------
local function routeOf(name: string): Route?
	local cached = routeCache[name]
	if cached then
		return cached
	end
	local city = ctx and ctx.Config and ctx.Config.City
	if not city or type(city.RoutePoints) ~= "function" then
		return nil
	end
	local ok, points = pcall(city.RoutePoints, name)
	if not ok or type(points) ~= "table" or #points < 2 then
		return nil
	end
	local cum: { number } = { 0 }
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
		cum[i] = length
	end
	if length <= 0 then
		return nil
	end
	local route: Route = { Points = points, Cum = cum, Length = length }
	routeCache[name] = route
	return route
end

local function pointAt(route: Route, f: number): (Vector3, Vector3)
	local target = (f % 1) * route.Length
	local points, cum = route.Points, route.Cum
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = points[lo], points[math.min(lo + 1, #points)]
	local seg = cum[math.min(lo + 1, #cum)] - cum[lo]
	local t = if seg > 0 then (target - cum[lo]) / seg else 0
	local dir = b - a
	return a:Lerp(b, t), if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(1, 0, 0)
end

local function routeFrame(route: Route, f: number, lift: number): CFrame
	local pos, dir = pointAt(route, f)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(1, 0, 0)
	end
	return CFrame.lookAt(pos + Vector3.new(0, lift, 0), pos + Vector3.new(0, lift, 0) + flat.Unit)
end

-- ---------------------------------------------------------------------
-- PICKUPS
-- ---------------------------------------------------------------------
local function poolKey(kind: string): string
	if string.sub(kind, 1, 5) == "Quiz:" then
		return "Pad"
	end
	if RECIPES[kind] then
		return kind
	end
	return "Coin"
end

local function acquire(key: string): Visual
	local pool = pools[key]
	if pool and #pool > 0 then
		local v = table.remove(pool) :: Visual
		setVisible(v, true)
		return v
	end
	return toVisual(build(key, RECIPES[key] or RECIPES.Coin))
end

local function release(key: string, v: Visual)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	if #pool >= POOL_MAX then
		destroyVisual(v)
		return
	end
	setVisible(v, false)
	table.insert(pool, v)
end

local function quizGui(token: TokenVis, questionId: number?)
	local letter = ({ "A", "B", "C" })[token.O] or "?"
	local answer = if questionId then T(("evt.quiz.%d.a%d"):format(questionId, token.O)) else ""
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AT_QuizLabel"
	billboard.Size = UDim2.fromOffset(220, 74)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Adornee = token.Visual.Parts[1]
	local frame = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = billboard,
	}, { UI.Corner(12), UI.Stroke(Theme.Accent, 1) })
	UI.Create("TextLabel", {
		Size = UDim2.new(0, 46, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = 30,
		TextColor3 = Theme.Accent,
		Text = letter,
		Parent = frame,
	})
	UI.Create("TextLabel", {
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -54, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text,
		Text = answer,
		Parent = frame,
	})
	billboard.Parent = gui
	token.Gui = billboard
end

local function pressActor(): Actor?
	for _, actor in pairs(actors) do
		if actor.Kind == "Press" then
			return actor
		end
	end
	return nil
end

local function droneActor(): Actor?
	for _, actor in pairs(actors) do
		if actor.Kind == "Drones" then
			return actor
		end
	end
	return nil
end

local function addToken(raw: any)
	if type(raw) ~= "table" then
		return
	end
	local id, kind, pos, untilT = raw.Id, raw.Kind, raw.Pos, raw.Until
	if type(id) ~= "number" or type(kind) ~= "string" or typeof(pos) ~= "Vector3" or type(untilT) ~= "number" then
		return
	end
	if tokens[id] then
		return
	end
	local cfg = eventsCfg()
	local t = now()
	local key = poolKey(kind)
	local readyAt = t
	if kind == "Coin" then
		readyAt = t + num(cfg.MoneyRain and cfg.MoneyRain.FallSeconds, 1.6)
	elseif kind == "Package" then
		local drones = droneActor()
		local drop = num(cfg.Drones and cfg.Drones.DropSeconds, 8)
		readyAt = if drones then math.max(t, drones.Started + drop) else t + drop
	elseif kind == "Orb" then
		readyAt = t + 0.5
	elseif key == "Pad" then
		local press = pressActor()
		readyAt = if press then math.max(t, press.Started + 4) else t
	end
	local q, o = 0, 0
	if key == "Pad" then
		local qs, os_ = string.match(kind, "^Quiz:(%d+):(%d+)$")
		q, o = tonumber(qs) or 0, tonumber(os_) or 0
	end
	local visual = acquire(key)
	local token: TokenVis = {
		Id = id,
		Kind = kind,
		Pos = pos,
		Until = untilT,
		Born = t,
		Ready = readyAt,
		Visual = visual,
		Base = key,
		Requested = -math.huge,
		Q = q,
		O = o,
		Gui = nil,
		Phase = math.random() * math.pi * 2,
	}
	tokens[id] = token
	if key == "Pad" then
		local press = pressActor()
		local ids = press and press.Data.Quiz
		local questionId = if type(ids) == "table" then ids[q] else nil
		quizGui(token, questionId)
		if press then
			press.Extra.Question = q
		end
	end
	queueMove(visual, CFrame.new(pos + Vector3.new(0, if kind == "Coin" then COIN_FALL else 0, 0)))
end

local function removeToken(id: number)
	local token = tokens[id]
	if not token then
		return
	end
	tokens[id] = nil
	if token.Gui then
		token.Gui:Destroy()
		token.Gui = nil
	end
	release(token.Base, token.Visual)
end

-- schwebendes "+120 CR"-Schild (Pool von 6)
local function floatText(pos: Vector3, text: string, color: Color3)
	local entry = nil
	local t = os.clock()
	for _, candidate in ipairs(floatPool) do
		if candidate.Until <= t then
			entry = candidate
			break
		end
	end
	if not entry then
		if #floatPool >= FLOAT_TEXTS then
			entry = floatPool[1]
		else
			local anchor = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
			anchor.Name = "AT_FloatAnchor"
			anchor.Parent = folder
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(160, 40)
			billboard.AlwaysOnTop = true
			billboard.LightInfluence = 0
			billboard.Adornee = anchor
			billboard.Parent = gui
			local label = UI.Create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = UI.Faces.MonoBold,
				TextSize = 24,
				Text = "",
				Parent = billboard,
			})
			UI.TextStroke(1).Parent = label
			entry = { Gui = billboard, Label = label, Anchor = anchor, Until = 0 }
			table.insert(floatPool, entry)
		end
	end
	local chosen = entry :: { Gui: BillboardGui, Label: TextLabel, Anchor: Part, Until: number }
	chosen.Until = t + 1.2
	chosen.Anchor.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	chosen.Label.Text = text
	chosen.Label.TextColor3 = color
	chosen.Label.TextTransparency = 0
	chosen.Gui.Enabled = not photoHidden
	chosen.Gui.StudsOffset = Vector3.zero
	TweenService:Create(
		chosen.Gui,
		TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 3.5, 0) }
	):Play()
	TweenService
		:Create(
			chosen.Label,
			TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		)
		:Play()
end

local function canRequest(t: number): boolean
	while requestTimes[1] ~= nil and t - requestTimes[1] > 1 do
		table.remove(requestTimes, 1)
	end
	return #requestTimes < REQUESTS_PER_SECOND
end

local function requestPickup(token: TokenVis)
	local t = os.clock()
	if t - token.Requested < REQUEST_GAP or not canRequest(t) then
		return
	end
	token.Requested = t
	table.insert(requestTimes, t)
	local id, pos, kind = token.Id, token.Pos, token.Kind
	task.spawn(function()
		if not ctx or type(ctx.RequestFull) ~= "function" then
			return
		end
		local reply = ctx.RequestFull("EventPickup", { Id = id }, true)
		if reply.Ok then
			removeToken(id)
			local credits = num(reply.Credits, 0)
			local effects = module("Effects")
			if kind == "Orb" then
				sfx("Pickup", pos, { Speed = 1.2 })
				if effects and type(effects.Burst) == "function" then
					pcall(effects.Burst, pos, COSMIC, 10, false)
				end
			elseif string.sub(kind, 1, 5) ~= "Quiz:" then
				sfx(if kind == "Coin" then "MoneyRain" else "Pickup", pos, nil)
				if effects and type(effects.Burst) == "function" then
					pcall(effects.Burst, pos, Theme.Up, 8, false)
				end
			end
			if credits > 0 then
				local format = ctx.Format
				local text = "+" .. tostring(credits)
				if format and type(format.Credits) == "function" then
					local ok, value = pcall(format.Credits, credits, lang())
					if ok then
						text = "+" .. value .. " CR"
					end
				end
				floatText(pos, text, Theme.Up)
				tryModule("Hud", "PulseCredits", credits)
			end
		elseif type(reply.Message) == "string" and reply.Message == T("evt.pickupGone") then
			removeToken(id) -- schon gesammelt/abgelaufen
		end
	end)
end

local function stepTokens(dt: number, t: number)
	collectAcc += dt
	local check = collectAcc >= COLLECT_CHECK
	if check then
		collectAcc = 0
	end
	local root = rootOf()
	local rootPos = if root then root.Position else nil
	local expired: { number } = {}
	local clock = os.clock()
	for id, token in pairs(tokens) do
		if t > token.Until then
			table.insert(expired, id)
			continue
		end
		local pos = token.Pos
		local cf: CFrame
		if token.Kind == "Coin" then
			local fall = math.max(0.01, token.Ready - token.Born)
			local f = math.clamp((t - token.Born) / fall, 0, 1)
			local eased = 1 - (1 - f) ^ 2
			local y = COIN_FALL * (1 - eased)
			cf = CFrame.new(pos + Vector3.new(0, y + math.sin(clock * 3 + token.Phase) * 0.25, 0))
				* CFrame.Angles(0, clock * 3 + token.Phase, math.pi / 2)
		elseif token.Kind == "Package" then
			local drop = math.max(0.01, token.Ready - token.Born)
			local f = math.clamp((t - token.Born) / drop, 0, 1)
			cf = CFrame.new(pos + Vector3.new(0, (1 - f) * DRONE_HEIGHT * 0.2 + 1.2, 0))
				* CFrame.Angles(0, token.Phase, 0)
		elseif token.Kind == "Orb" then
			cf = CFrame.new(pos + Vector3.new(0, math.sin(clock * 2 + token.Phase) * 0.6, 0))
		elseif token.Base == "Pad" then
			cf = CFrame.new(pos)
		else
			cf = CFrame.new(pos + Vector3.new(0, math.sin(clock * 2.4 + token.Phase) * 0.3, 0))
				* CFrame.Angles(0, clock * 1.5 + token.Phase, 0)
		end
		queueMove(token.Visual, cf)
		if check and rootPos and t >= token.Ready then
			local d = rootPos - pos
			if token.Base == "Pad" then
				if Vector2.new(d.X, d.Z).Magnitude <= QUIZ_RANGE and math.abs(d.Y) < 7 then
					requestPickup(token)
				end
			elseif d.Magnitude <= AUTO_RANGE then
				requestPickup(token)
			end
		end
	end
	for _, id in ipairs(expired) do
		removeToken(id)
	end
end

-- ---------------------------------------------------------------------
-- WELT-DARSTELLER
-- ---------------------------------------------------------------------
local function actorKey(state: any): string?
	if type(state) ~= "table" or type(state.Kind) ~= "string" or type(state.Started) ~= "number" then
		return nil
	end
	return state.Kind .. "@" .. tostring(math.floor(state.Started))
end

local function countActors(): number
	local n = 0
	for _ in pairs(actors) do
		n += 1
	end
	return n
end

local function plotSites(): { CFrame }
	local out: { CFrame } = {}
	local city = ctx and ctx.Config and ctx.Config.City
	local plots = math.floor(num(ctx and ctx.Config and ctx.Config.Server and ctx.Config.Server.Plots, 10))
	if city and type(city.PlotCFrame) == "function" then
		for k = 1, plots do
			local ok, cf = pcall(city.PlotCFrame, k)
			if ok and typeof(cf) == "CFrame" then
				table.insert(out, cf)
			end
		end
	end
	return out
end

-- Pressekonferenz-Tafel (Firmen von :03 des nächsten Börsentags + aktuelle Quiz-Frage)
local function pressBoard(actor: Actor, anchorPart: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AT_PressBoard"
	billboard.Size = UDim2.fromOffset(420, 250)
	billboard.StudsOffset = Vector3.new(0, 16, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Adornee = anchorPart
	local frame = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = billboard,
	}, {
		UI.Corner(16),
		UI.Stroke(Theme.Accent, 1),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		}),
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	UI.Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = 18,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = T("evt.press.title"),
		LayoutOrder = 1,
		Parent = frame,
	})
	local body = UI.Create("TextLabel", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text2,
		Text = "",
		LayoutOrder = 2,
		Parent = frame,
	})
	local question = UI.Create("TextLabel", {
		Name = "Question",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 16,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Accent,
		Text = "",
		LayoutOrder = 3,
		Parent = frame,
	})
	billboard.Parent = gui
	actor.Extra.Board = billboard
	actor.Extra.Body = body
	actor.Extra.QuestionLabel = question
end

local function companyName(i: number): string
	local companies = ctx and ctx.Config and ctx.Config.Companies
	local byId = companies and companies.ById
	local entry = byId and byId[i]
	if type(entry) == "table" then
		local name = entry.Name
		local text = if type(name) == "table" then (name[lang()] or name.de or "") else tostring(name or "")
		return ("%s · %s"):format(tostring(entry.Ticker or i), text)
	end
	return tostring(i)
end

local function consensusText(profile: any): string
	if type(profile) ~= "table" then
		return T("evt.press.consPending")
	end
	local cons = profile.Consensus
	local text = if cons == "Up"
		then T("evt.press.consUp")
		elseif cons == "Down" then T("evt.press.consDown")
		elseif cons == "Flat" then T("evt.press.consFlat")
		else T("evt.press.consPending")
	local beat, miss = 0, 0
	if type(profile.Analysts) == "table" then
		for _, a in ipairs(profile.Analysts) do
			if type(a) == "table" then
				if a.Verdict == 1 then
					beat += 1
				elseif a.Verdict == -1 then
					miss += 1
				end
			end
		end
	end
	if beat + miss > 0 then
		text ..= " · " .. T("evt.press.verdicts", beat, miss)
	end
	return text
end

local function refreshPressBoard(actor: Actor)
	local body: TextLabel? = actor.Extra.Body
	if not body then
		return
	end
	local items = actor.Data.Items
	local rows: { string } = {}
	if type(items) == "table" and #items > 0 then
		for _, item in ipairs(items) do
			if type(item) == "table" and type(item.I) == "number" then
				local cached = profileCache[item.I]
				table.insert(
					rows,
					("<b>%s</b>\n%s"):format(companyName(item.I), consensusText(if cached then cached.Profile else nil))
				)
			end
		end
	else
		table.insert(rows, T("evt.press.noItems"))
	end
	body.Text = table.concat(rows, "\n")
	local question: TextLabel? = actor.Extra.QuestionLabel
	if question then
		local ids = actor.Data.Quiz
		local q = actor.Extra.Question
		local id = if type(ids) == "table" and type(q) == "number" then ids[q] else nil
		question.Text = if id
			then T("evt.press.question", q, #ids, T(("evt.quiz.%d.q"):format(id)))
			else T("evt.press.quizHint")
	end
end

-- Profile der berichtenden Firmen einmal je Pressekonferenz holen (MktProfile, Konsens/Urteile soweit freigegeben)
local function fetchPressProfiles(actor: Actor)
	if pressRequested[actor.Key] then
		return
	end
	pressRequested[actor.Key] = true
	local items = actor.Data.Items
	if type(items) ~= "table" then
		return
	end
	task.spawn(function()
		for index, item in ipairs(items) do
			if index > 4 or not actors[actor.Key] then
				break
			end
			if type(item) == "table" and type(item.I) == "number" and ctx and type(ctx.RequestFull) == "function" then
				local reply = ctx.RequestFull("MktProfile", { I = item.I }, true)
				if reply.Ok and type(reply.Profile) == "table" then
					profileCache[item.I] = { At = os.clock(), Profile = reply.Profile }
				end
				refreshPressBoard(actor)
				task.wait(0.4)
			end
		end
	end)
end

-- Top-10-Hologramm (Bilanz-Sonntag): nur Rang + Name, keine Werte
local function finaleBoard(actor: Actor, anchorPart: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AT_FinaleBoard"
	billboard.Size = UDim2.fromOffset(320, 360)
	billboard.StudsOffset = Vector3.new(0, 18, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Adornee = anchorPart
	local frame = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = billboard,
	}, {
		UI.Corner(16),
		UI.Stroke(GOLD, 1),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 10),
		}),
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
	})
	UI.Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = 18,
		TextColor3 = GOLD,
		Text = T("evt.finale.title"),
		LayoutOrder = 0,
		Parent = frame,
	})
	local top = actor.Data.Top
	if type(top) == "table" then
		for i, name in ipairs(top) do
			if i > 10 then
				break
			end
			UI.Create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				FontFace = if i <= 3 then UI.Faces.BodyBold else UI.Faces.Body,
				TextSize = if i <= 3 then 19 else 16,
				TextColor3 = if i == 1 then GOLD elseif i <= 3 then Theme.Text else Theme.Text2,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = ("%d.  %s"):format(i, tostring(name)),
				LayoutOrder = i,
				Parent = frame,
			})
		end
	end
	billboard.Parent = gui
	actor.Extra.Board = billboard
end

local function spawnActor(state: any): Actor?
	local key = actorKey(state)
	if not key or countActors() >= MAX_ACTORS then
		return nil
	end
	local data = if type(state.Data) == "table" then state.Data else {}
	local actor: Actor = {
		Key = key,
		Kind = state.Kind,
		Started = state.Started,
		Until = num(state.Until, state.Started),
		Data = data,
		Visuals = {},
		Extra = {},
		Leaving = nil,
	}
	local kind = state.Kind
	if kind == "Truck" then
		table.insert(actor.Visuals, toVisual(build("Truck", RECIPES.Truck)))
	elseif kind == "Drones" then
		local spots = data.Spots
		if type(spots) == "table" then
			for i, spot in ipairs(spots) do
				if i > 12 then
					break
				end
				if typeof(spot) == "Vector3" then
					table.insert(actor.Visuals, toVisual(build("Drone", RECIPES.Drone)))
				end
			end
		end
	elseif kind == "BuildBoom" then
		for _ in ipairs(plotSites()) do
			table.insert(actor.Visuals, toVisual(build("Crane", RECIPES.Crane)))
		end
	elseif kind == "Press" then
		local visual = toVisual(build("Hologram", RECIPES.Hologram))
		table.insert(actor.Visuals, visual)
		if visual.Parts[1] then
			pressBoard(actor, visual.Parts[1])
		end
		fetchPressProfiles(actor)
	elseif kind == "Bear" then
		table.insert(actor.Visuals, toVisual(build("Bear", RECIPES.Bear)))
	elseif kind == "GoldenBull" then
		table.insert(actor.Visuals, toVisual(build("Bull", RECIPES.Bull)))
	elseif kind == "Parade" then
		local count = math.clamp(math.floor(num(data.Bulls, 5)), 1, 8)
		for _ = 1, count do
			table.insert(actor.Visuals, toVisual(build("Bull", RECIPES.Bull)))
		end
		local lead = actor.Visuals[1]
		if lead and lead.Parts[1] then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "AT_ParadeThanks"
			billboard.Size = UDim2.fromOffset(280, 46)
			billboard.StudsOffset = Vector3.new(0, 11, 0)
			billboard.LightInfluence = 0
			billboard.MaxDistance = 300
			billboard.Adornee = lead.Parts[1]
			local label = UI.Create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.Surface,
				BackgroundTransparency = 0.15,
				FontFace = UI.Faces.Display,
				TextSize = 20,
				TextColor3 = GOLD,
				Text = T("evt.paradeBanner", tostring(data.Name or "?")),
				Parent = billboard,
			}, { UI.Corner(12), UI.Stroke(GOLD, 1) })
			billboard.Parent = gui
			actor.Extra.Board = billboard
			actor.Extra.Label = label
		end
	elseif kind == "LeagueFinale" then
		local anchorPart = part({ Name = "AT_FinaleAnchor", Size = Vector3.new(1, 1, 1), Transparency = 1 })
		local ring = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 18, 18),
			Color = GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})
		local m = newModel("AT_Finale", { anchorPart, ring })
		ring.CFrame = CFrame.Angles(0, 0, math.pi / 2)
		local visual = toVisual(m)
		table.insert(actor.Visuals, visual)
		finaleBoard(actor, anchorPart)
	else
		return nil -- Events ohne Darsteller (Golden Hour, XP-Rausch, Power-Hour …)
	end
	actors[key] = actor
	return actor
end

local function removeActor(key: string)
	local actor = actors[key]
	if not actor then
		return
	end
	actors[key] = nil
	for _, v in ipairs(actor.Visuals) do
		destroyVisual(v)
	end
	local board = actor.Extra.Board
	if typeof(board) == "Instance" then
		board:Destroy()
	end
	pressRequested[key] = nil
end

local function updateActor(actor: Actor, t: number, dt: number)
	local kind = actor.Kind
	local data = actor.Data
	local duration = math.max(1, actor.Until - actor.Started)
	local f = math.clamp((t - actor.Started) / duration, 0, 1)
	if kind == "Truck" then
		local route = routeOf(data.Route or "Ring")
		local v = actor.Visuals[1]
		if route and v then
			queueMove(v, routeFrame(route, f, 0))
		end
	elseif kind == "Drones" then
		local spots = data.Spots
		local drop = num(data.Drop, 8)
		local elapsed = t - actor.Started
		for i, v in ipairs(actor.Visuals) do
			local spot = if type(spots) == "table" then spots[i] else nil
			if typeof(spot) == "Vector3" then
				local height: number
				if elapsed < drop then
					local g = elapsed / drop
					height = DRONE_HEIGHT * (1 - (1 - (1 - g) ^ 3)) + 5
				elseif elapsed < drop + 1.5 then
					height = 5
				else
					height = 5 + (elapsed - drop - 1.5) * 18
				end
				local spin = os.clock() * 0.8 + i
				queueMove(v, CFrame.new(spot + Vector3.new(0, height, 0)) * CFrame.Angles(0, spin, 0))
				local cargo = v.Model:FindFirstChild("Cargo")
				if cargo and cargo:IsA("BasePart") then
					local want = if elapsed < drop then 0 else 1
					if cargo.Transparency ~= want then
						cargo.Transparency = want
					end
				end
			end
		end
	elseif kind == "BuildBoom" then
		local sites = plotSites()
		for i, v in ipairs(actor.Visuals) do
			local site = sites[i]
			if site then
				local toCenter = plazaCenter() - site.Position
				local flat = Vector3.new(toCenter.X, 0, toCenter.Z)
				local side = if flat.Magnitude > 1
					then Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
					else Vector3.new(1, 0, 0)
				local base = site.Position + side * 34
				queueMove(v, CFrame.new(base) * CFrame.Angles(0, os.clock() * 0.15 + i, 0))
			end
		end
	elseif kind == "Press" then
		local v = actor.Visuals[1]
		local pos = if typeof(data.Pos) == "Vector3" then data.Pos else attrVector("AT_PressPos")
		local look = if typeof(data.Look) == "Vector3" then data.Look else attrVector("AT_PressLook")
		if v and pos then
			local dir = if look and look.Magnitude > 0.01 then look else Vector3.new(0, 0, 1)
			local front = pos + dir * 12
			local bob = math.sin(os.clock() * 1.6) * 0.3
			queueMove(v, CFrame.lookAt(front + Vector3.new(0, bob, 0), front + Vector3.new(0, bob, 0) + dir))
		end
		actor.Extra.RefreshAcc = num(actor.Extra.RefreshAcc, 0) + dt
		if actor.Extra.RefreshAcc >= 1 then
			actor.Extra.RefreshAcc = 0
			refreshPressBoard(actor)
		end
	elseif kind == "Bear" then
		local v = actor.Visuals[1]
		if v then
			local center = plazaCenter()
			local elapsed = t - actor.Started
			local walk = math.clamp(elapsed / BEAR_WALK, 0, 1)
			local from = center + Vector3.new(0, 0, 120)
			local pos = from:Lerp(center + Vector3.new(0, 0, 12), 1 - (1 - walk) ^ 2)
			local stomp = math.abs(math.sin(os.clock() * (if walk < 1 then 5 else 2.2)))
				* (if walk < 1 then 0.8 else 0.35)
			local sway = math.sin(os.clock() * 2.2) * 0.06
			local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
				* CFrame.new(0, stomp, 0)
				* CFrame.Angles(0, 0, sway)
			local leaving = actor.Leaving
			if leaving then
				local g = math.clamp((os.clock() - leaving) / 6, 0, 1)
				if actor.Extra.Success then
					-- verbeugen (1,5 s), dann gemächlich davon
					local bow = math.clamp((os.clock() - leaving) / 1.5, 0, 1)
					cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
						* CFrame.Angles(-0.45 * math.sin(bow * math.pi), 0, 0)
					if g > 0.25 then
						local away = (g - 0.25) / 0.75
						cf = CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1)) + Vector3.new(0, 0, -away * 110)
					end
				else
					cf = CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1)) + Vector3.new(0, 0, -g * 110)
				end
			end
			queueMove(v, cf)
		end
	elseif kind == "GoldenBull" then
		local route = routeOf(data.Route or "Ring")
		local v = actor.Visuals[1]
		if route and v then
			local bob = math.abs(math.sin(os.clock() * 7)) * 0.6
			queueMove(v, routeFrame(route, f, bob))
		end
	elseif kind == "Parade" then
		local route = routeOf(data.Route or "Parade")
		if route then
			local cfg = eventsCfg()
			local lap = num(cfg.Parade and cfg.Parade.LapSeconds, 150)
			local base = ((t - actor.Started) / lap) % 1
			for i, v in ipairs(actor.Visuals) do
				local offset = (i - 1) * PARADE_GAP / route.Length
				local bob = math.abs(math.sin(os.clock() * 6 + i)) * 0.5
				queueMove(v, routeFrame(route, base - offset, bob))
			end
		end
	elseif kind == "LeagueFinale" then
		local v = actor.Visuals[1]
		local pos = if typeof(data.Pos) == "Vector3" then data.Pos else attrVector("AT_HallPos")
		if v and pos then
			queueMove(v, CFrame.new(pos + Vector3.new(0, 0.3, 0)))
		end
	end
end

-- Darsteller mit dem State abgleichen (neue anlegen, beendete entfernen, Verlängerungen übernehmen)
local function syncActors(list: any)
	local t = now()
	local seen: { [string]: boolean } = {}
	if type(list) == "table" then
		for _, state in ipairs(list) do
			local key = actorKey(state)
			if key and num(state.Until, 0) > t then
				seen[key] = true
				local actor = actors[key]
				if actor then
					actor.Until = num(state.Until, actor.Until)
					if type(state.Data) == "table" then
						actor.Data = state.Data
					end
				else
					spawnActor(state)
				end
			end
		end
	end
	for key, actor in pairs(actors) do
		if not seen[key] and not actor.Leaving then
			if actor.Kind == "Bear" then
				actor.Leaving = os.clock()
				actor.Until = t + 7
			else
				removeActor(key)
			end
		end
	end
end

local function onWorldEvent(state: any)
	local key = actorKey(state)
	if not key then
		return
	end
	local t = now()
	if num(state.Until, 0) <= t then
		local actor = actors[key]
		if actor then
			if actor.Kind == "Bear" and not actor.Leaving then
				actor.Leaving = os.clock()
				actor.Until = t + 7
			elseif actor.Kind ~= "Bear" then
				removeActor(key)
			end
		end
	else
		local actor = actors[key]
		if actor then
			actor.Until = num(state.Until, actor.Until)
			if type(state.Data) == "table" then
				actor.Data = state.Data
			end
		else
			spawnActor(state)
		end
	end
end

-- ---------------------------------------------------------------------
-- GOLDEN HOUR (Welt-Tönung), GLOCKEN-ZONE, BÄR-LEISTE, WARTUNGS-BANNER
-- ---------------------------------------------------------------------
local function updateGolden(t: number)
	local active = false
	for _, state in ipairs(EventsClient.Active()) do
		if state.Kind == "GoldenHour" and num(state.Until, 0) > t then
			active = true
			break
		end
	end
	if active and not goldenSet then
		local ok = tryModule("WorldLook", "SetOverride", "Golden")
		goldenSet = ok
	elseif not active and goldenSet then
		goldenSet = false
		tryModule("WorldLook", "SetOverride", nil)
	end
end

local function bellWindowOpen(t: number): boolean
	local clock = ctx and ctx.Clock
	if not clock then
		return false
	end
	local cfg = eventsCfg().BellMoment or {}
	local tick = math.floor(t) - num(clock.EPOCH, 0)
	local dayTicks = num(clock.DAY_TICKS, 1200)
	local day = tick // dayTicks
	local within = tick % dayTicks
	return day % math.max(1, math.floor(num(cfg.DayEvery, 3))) == 0 and within < num(cfg.WindowSeconds, 60)
end

local function updateBellZone(t: number)
	local center = attrVector("AT_BellZone")
	local radius = num(workspace:GetAttribute("AT_BellZoneRadius"), 18)
	local momentLive = false
	for _, state in ipairs(EventsClient.Active()) do
		if state.Kind == "BellMoment" and num(state.Until, 0) > t then
			momentLive = true
			break
		end
	end
	local show = center ~= nil and (bellWindowOpen(t) or momentLive)
	local glow = bellRing and bellRing:FindFirstChild("AT_EventLight")
	if glow and glow:IsA("Light") and glow.Enabled ~= show then
		glow.Enabled = show -- goldener Bodenschein nur, solange die Zone offen ist
	end
	if not show then
		if bellRing then
			bellRing.Transparency = 1
		end
		if bellGui then
			bellGui.Enabled = false
		end
		return
	end
	if not bellRing then
		local ring = part({
			Name = "AT_BellZone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 2, radius * 2),
			Color = GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
		})
		addLight(ring, "PointLight", 16, { Range = math.min(radius + 6, 60), Brightness = 1.1, Color = GOLD })
		ring.Parent = folder
		bellRing = ring
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(260, 40)
		billboard.StudsOffset = Vector3.new(0, 8, 0)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 250
		billboard.Adornee = ring
		local label = UI.Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Surface,
			BackgroundTransparency = 0.15,
			FontFace = UI.Faces.BodyBold,
			TextSize = 18,
			TextColor3 = GOLD,
			Text = "",
			Parent = billboard,
		}, { UI.Corner(12), UI.Stroke(GOLD, 1) })
		billboard.Parent = gui
		bellGui = billboard
		bellLabel = label
	end
	local ring = bellRing :: Part
	local pulse = 0.55 + math.sin(os.clock() * 4) * 0.12
	ring.Transparency = pulse
	ring.CFrame = CFrame.new((center :: Vector3) + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	-- Spieler in der Zone (Anzeige; der Server zählt verbindlich)
	local inside = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d = root.Position - (center :: Vector3)
			if Vector2.new(d.X, d.Z).Magnitude <= radius + 2 and math.abs(d.Y) < 40 then
				inside += 1
			end
		end
	end
	local needed = math.floor(num(eventsCfg().BellMoment and eventsCfg().BellMoment.MinPlayers, 3))
	local studio = ctx and ctx.State and ctx.State.Server and ctx.State.Server.Studio == true
	if studio then
		needed = math.floor(num(ctx.Config.Studio and ctx.Config.Studio.BellZoneMinPlayers, 1))
	end
	if bellGui and bellLabel then
		bellGui.Enabled = not photoHidden
		bellLabel.Text = if momentLive then T("evt.bellZoneLive") else T("evt.bellZone", inside, math.max(1, needed))
	end
end

local function updateBearBar()
	local bar, fill, label = bearBar, bearFill, bearLabel
	if not bar or not fill or not label then
		return
	end
	local show = bearGoal > 0 and not photoHidden
	bar.Visible = show
	if show then
		local ratio = math.clamp(bearHave / math.max(1, bearGoal), 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(ratio, 1) })
			:Play()
		label.Text = T("evt.bearProgress", bearHave, bearGoal)
	end
end

local function updateBanner()
	local frame, label = banner, bannerLabel
	if not frame or not label then
		return
	end
	local text = workspace:GetAttribute("AT_Maintenance")
	local show = type(text) == "string" and text ~= "" and not photoHidden
	frame.Visible = show
	if show then
		label.Text = T("evt.maintenance", text :: string)
	end
end

local function buildUi()
	local screen = UI.Create("ScreenGui", {
		Name = "AkytexTycoonEvents",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 2,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	gui = screen
	-- Bär-Fortschritt (oben Mitte, unter den HUD-Pillen)
	local bar = UI.Create("Frame", {
		Name = "BearBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(300, 34),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screen,
	}, { UI.Corner(17), UI.Stroke(nil, 1) })
	local track = UI.Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -6),
		Size = UDim2.new(1, -28, 0, 4),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = bar,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local fill = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COSMIC,
		BorderSizePixel = 0,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local label = UI.Create("TextLabel", {
		Position = UDim2.fromOffset(14, 2),
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Text = "",
		Parent = bar,
	})
	bearBar, bearFill, bearLabel = bar, fill, label
	-- Wartungs-Banner (Live-Ops-Notschalter)
	local strip = UI.Create("Frame", {
		Name = "Maintenance",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.6, 0, 0, 30),
		BackgroundColor3 = Theme.Warn,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	}, { UI.Corner(10) })
	local stripLabel = UI.Create("TextLabel", {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 15,
		TextColor3 = DARK,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = 6,
		Parent = strip,
	})
	banner, bannerLabel = strip, stripLabel
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API + LEBENSZYKLUS
-- ---------------------------------------------------------------------
function EventsClient.Active(): { any }
	local state = ctx and ctx.State and ctx.State.Event
	local list = if type(state) == "table" and type(state.Active) == "table" then state.Active else {}
	local t = now()
	local out: { any } = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" and num(entry.Until, 0) > t then
			table.insert(out, entry)
		end
	end
	return out
end

function EventsClient.Frame(dt: number)
	local t = now()
	stepTokens(dt, t)
	local finished: { string } = {}
	for key, actor in pairs(actors) do
		if t > actor.Until + (if actor.Leaving then 0 else 2) then
			table.insert(finished, key)
		else
			updateActor(actor, t, dt)
		end
	end
	for _, key in ipairs(finished) do
		removeActor(key)
	end
	-- schwebende CR-Schilder ausblenden, wenn abgelaufen
	local clock = os.clock()
	for _, entry in ipairs(floatPool) do
		if entry.Until <= clock and entry.Gui.Enabled then
			entry.Gui.Enabled = false
		end
	end
	flushMoves()
	bellAcc += dt
	if bellAcc >= BELL_CHECK then
		bellAcc = 0
		updateBellZone(t)
		updateGolden(t)
	end
	local effectsEvent = module("EffectsEvent")
	if effectsEvent and type(effectsEvent.Step) == "function" then
		local ok, err = pcall(effectsEvent.Step, dt)
		if not ok then
			warn("[EventsClient] EffectsEvent.Step: " .. tostring(err))
		end
	end
end

function EventsClient.Init(context: any)
	ctx = context
	local ok, slotModule = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetSlot")) :: any
	end)
	AssetSlot = if ok then slotModule else nil
	local f = Instance.new("Folder")
	f.Name = "AT_EventLocal"
	f.Parent = workspace
	folder = f
	buildUi()
end

function EventsClient.Start()
	local hooks = ctx.Hooks
	hooks.On("World:Pickups", function(list: any)
		if type(list) ~= "table" then
			return
		end
		for i, raw in ipairs(list) do
			if i > 60 then
				break
			end
			addToken(raw)
		end
		flushMoves()
	end)
	hooks.On("World:PickupGone", function(data: any)
		if type(data) == "table" and type(data.Id) == "number" then
			removeToken(data.Id)
		end
	end)
	hooks.On("World:Event", onWorldEvent)
	hooks.On("World:Bear", function(data: any)
		if type(data) == "table" then
			bearHave = math.max(0, math.floor(num(data.Have, 0)))
			bearGoal = math.max(0, math.floor(num(data.Goal, 0)))
			updateBearBar()
		end
	end)
	hooks.On("World:Parade", function(data: any)
		-- Parade kommt zusätzlich als World:Event (Darsteller); hier nur die Verlängerung übernehmen
		if type(data) ~= "table" then
			return
		end
		for _, actor in pairs(actors) do
			if actor.Kind == "Parade" then
				actor.Until = math.max(actor.Until, num(data.Until, actor.Until))
			end
		end
	end)
	hooks.On("Effect:Bear", function(_strength: any, data: any)
		if type(data) ~= "table" then
			return
		end
		if data.Phase == "Success" or data.Phase == "Leave" then
			for _, actor in pairs(actors) do
				if actor.Kind == "Bear" and not actor.Leaving then
					actor.Leaving = os.clock()
					actor.Extra.Success = data.Phase == "Success"
					actor.Until = now() + 7
				end
			end
			bearHave, bearGoal = 0, 0
			updateBearBar()
		end
	end)
	hooks.On("State", function(state: any, changed: any)
		if type(changed) == "table" and changed.Event and type(state) == "table" then
			local event = state.Event
			if type(event) == "table" then
				syncActors(event.Active)
				bearHave = math.max(0, math.floor(num(event.BearHave, bearHave)))
				bearGoal = math.max(0, math.floor(num(event.BearGoal, 0)))
				updateBearBar()
			end
		end
	end)
	hooks.On("PhotoMode", function(on: any)
		photoHidden = on == true
		updateBearBar()
		updateBanner()
		for _, token in pairs(tokens) do
			if token.Gui then
				token.Gui.Enabled = not photoHidden
			end
		end
		for _, actor in pairs(actors) do
			local board = actor.Extra.Board
			if typeof(board) == "Instance" and board:IsA("BillboardGui") then
				board.Enabled = not photoHidden
			end
		end
	end)
	workspace:GetAttributeChangedSignal("AT_Maintenance"):Connect(updateBanner)
	player.CharacterAdded:Connect(function()
		collectAcc = 0
	end)
	updateBanner()
	-- erster Stand (State kann schon vor Start angekommen sein)
	local event = ctx.State and ctx.State.Event
	if type(event) == "table" then
		syncActors(event.Active)
	end
end

return EventsClient
