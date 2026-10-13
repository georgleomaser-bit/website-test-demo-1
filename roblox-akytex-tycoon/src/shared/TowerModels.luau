--!strict
-- =====================================================================
--  AKYTEX TYCOON – Tower-Rezepte als PartSpecs (Shared/TowerModels)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C6.2 (TowerModels), §B4.1 (Maße),
--  §B4.2 (12 Silhouetten), §B4.3/§B4.4/§B4.5 (Abteilungen, Personal-Roboter, Raum-Stufen), §B4.8 (Deko-Plätze),
--  §B4.9 (Fassaden, Neon, Kronen), §B3 (Hülle ≤ 8 Parts/Etage, Krone ≤ 60, Plot-Ausstattung ≤ 40, Interior ≤ 150
--  Parts/Etage), §C12.3 (Plot-Attribut "Layout").
--
--  Deterministische Rezepte (gleich auf Server und Client): jede Funktion liefert eine Liste von PartSpecs –
--  reine Daten (Zahlen, Hex-Farben, Material-Namen), keine Roblox-Typen -> mit der Luau-CLI testbar. Erst
--  TowerModels.Instantiate/Apply (nur in Roblox aufgerufen) machen daraus BaseParts.
--  Koordinaten: Plot-lokal, Ursprung = Plot-Mitte auf dem Boden (Y = 0), −Z = vorn (Plot-LookVector zur Plaza),
--  +X = rechts. Etage n beginnt auf Höhe (n − 1) × 12; ihre Deckenplatte reicht bis (n − 1) × 12 + 1 (Füße der
--  Aufzugs-Ankunft, gleiche Konvention wie PlotService.FloorCFrame). Interiors sind Etagen-lokal (Y = 0 = Oberkante
--  der Deckenplatte), Kronen Dach-lokal (Y = 0 = Dachunterkante = Etagenzahl × 12).
--
--  Öffentliche API (§C6.2):
--    TowerModels.Shell(stage, floor, skin, neon): { PartSpec }          Hülle EINER Etage (≤ 8 Parts)
--    TowerModels.Interior(room, level, staff, decor, footprint?, floor?): { PartSpec }   ≤ 150 Parts
--    TowerModels.Crown(stage, crown, floors?, skin?, neon?): { PartSpec }   Dach + Krone + Börsengang-Krone (≤ 60)
--  Ergänzungen (abwärtskompatibel):
--    TowerModels.Spine(stage, floors, skin, neon)      senkrechte Teile: Ecksäulen je Grundriss-Abschnitt, Kern, Finnen
--    TowerModels.Site(stage, floors, skin, neon)       Plot-Ausstattung (Tresor, Kassen-Tor, Schild, Respekt-Säule …)
--    TowerModels.Preview(stage, floors, skin, neon, crown)   vereinfachter Tower (ViewportFrames, ≤ 220 Parts)
--    TowerModels.Robot(key, x, z, yaw, group): { PartSpec }  Personal-Roboter (Kugelkopf, Kapselkörper, Schwebering)
--    TowerModels.Footprint(stage, floor): number        40 / 56 / 52 / 48 (§B4.1)
--    TowerModels.StageOf(floors): number               1 … 12 (0 Etagen = Stufe 1)
--    TowerModels.Count(stage, floors): (total, maxFloor, spine, crown, site)   Teile-Budget einer Hülle
--    TowerModels.DecorSlots(room, footprint, floor?): { { X, Z, Yaw } }   feste Deko-Plätze einer Etage
--    TowerModels.EncodeLayout(floors, private): string  /  TowerModels.DecodeLayout(text): { FloorLayout }
--    TowerModels.Configure(towerCfg, decorCfg)          Codes/Geometrie aus Config.Tower + Config.Decor
--    TowerModels.SetDecorProvider(fn)                   DecorModels registriert hier seine Specs (Deko im Interior)
--    TowerModels.NeonHex(key) · TowerModels.Palette(skin, floor) · TowerModels.Hex(text) -> (r, g, b)
--    TowerModels.Instantiate(spec, origin, parent?): BasePart     TowerModels.Apply(part, spec, origin)
--    TowerModels.KindOf(spec): "Part" | "WedgePart" | "CornerWedgePart"
-- =====================================================================

local TowerModels = {}

export type LightSpec = {
	Kind: string?, -- "Point" (Standard) | "Spot" | "Surface"
	Range: number,
	Brightness: number,
	Color: string,
	Face: string?,
	Angle: number?,
}

export type PartSpec = {
	Kind: string?, -- "Part" (Standard) | "Wedge" | "CornerWedge"
	Shape: string?, -- "Block" | "Cylinder" | "Ball" (nur Kind "Part"; Zylinder-Achse = X)
	Size: { number },
	Pos: { number },
	Rot: { number }?, -- Grad, CFrame.fromOrientation (Y, dann X, dann Z)
	Color: string,
	Material: string,
	Transparency: number?,
	Reflectance: number?,
	Collide: boolean?,
	Query: boolean?,
	Shadow: boolean?,
	Tag: string?, -- Rolle: Slab, Facade, Neon, Core, Pillar, Roof, Vault, CashGate, Sign, Respekt, Led, Monitor …
	Group: string?, -- Teile mit gleicher Gruppe bewegen sich gemeinsam (Roboter, Drehteile)
	Anim: string?, -- Client-Animation: Bob, Spin, Sweep, Beacon, Lift, Fish, Arm, Patrol
	Light: LightSpec?,
	Attr: { [string]: any }?,
	Name: string?,
}

export type FloorLayout = { Room: string, Level: number, Staff: { string }, Decor: { string }, Private: boolean }
export type Slot = { X: number, Z: number, Yaw: number }

type Opts = { [string]: any }
type Group = { X: number, Y: number, Z: number, Yaw: number, C: number, S: number }
type Pal = { [string]: any }

-- ---------------------------------------------------------------------
-- 1) PARAMETER (Startwerte = DESIGN §B4; Configure übernimmt Config.Tower / Config.Decor)
-- ---------------------------------------------------------------------
local FH = 12 -- Etagenhöhe
local SLAB = 1 -- Deckenplatte
local CORE = 10 -- Aufzugskern 10 × 10
local SMALL, LARGE, LARGE_FROM = 40, 56, 5
local SETBACKS: { { number } } = { { 31, 52 }, { 41, 48 } }
local FLOORS = 50
local STAGE_FIRST: { number } = { 1, 2, 4, 7, 10, 14, 18, 22, 26, 31, 37, 44 }
local SLOTS_PER_FLOOR, PENTHOUSE_SLOTS = 3, 8
local MAX_INTERIOR = 150
local MAX_SHELL_FLOOR = 8
local MAX_CROWN = 60
local MAX_SITE = 40
local DOOR_W, DOOR_TOP = 8, 9

local ROOM_CODE: { [string]: string } = {
	Office = "O",
	Desk = "D",
	Cafe = "C",
	Garage = "G",
	Marketing = "M",
	Vault = "V",
	Lab = "L",
	Server = "S",
	Lounge = "U",
	BotLab = "B",
	Penthouse = "P",
}
local STAFF_CODE: { [string]: string } = {
	Intern = "I",
	Analyst = "A",
	Senior = "S",
	Quant = "Q",
	Janitor = "J",
	Security = "W",
}
local CODE_ROOM: { [string]: string } = {}
local CODE_STAFF: { [string]: string } = {}
local DECOR_CODE: { [string]: string } = {}
local CODE_DECOR: { [string]: string } = {}
local ROOM_SLOTS: { [string]: number } = { Penthouse = 8 }

local NEON_HEX: { [string]: string } = {
	Accent = "#4f8cff",
	Up = "#22c55e",
	Down = "#ef4444",
	Cyan = "#22d3ee",
	Purple = "#8b5cf6",
	Gold = "#facc15",
	Startup = "#7c9cff",
	Partner = "#ec4899",
	Returner = "#ffcf6e",
}
local CROWN_HEX: { [string]: string } = {
	Silver = "#c0c7d4",
	Gold = "#facc15",
	Platinum = "#e5e7eb",
	Holo = "#7c5cff",
	Orbit = "#b36bff",
}

local function rebuildCodes()
	table.clear(CODE_ROOM)
	table.clear(CODE_STAFF)
	table.clear(CODE_DECOR)
	for key, code in pairs(ROOM_CODE) do
		CODE_ROOM[code] = key
	end
	for key, code in pairs(STAFF_CODE) do
		CODE_STAFF[code] = key
	end
	for key, code in pairs(DECOR_CODE) do
		CODE_DECOR[code] = key
	end
end
rebuildCodes()

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isHex(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end

function TowerModels.Configure(towerCfg: any, decorCfg: any)
	if type(towerCfg) == "table" then
		if finite(towerCfg.FloorHeight) and towerCfg.FloorHeight >= 4 and towerCfg.FloorHeight <= 40 then
			FH = towerCfg.FloorHeight
		end
		if finite(towerCfg.Floors) and towerCfg.Floors >= 1 and towerCfg.Floors <= 50 then
			FLOORS = math.floor(towerCfg.Floors)
		end
		local geo = towerCfg.Geometry
		if type(geo) == "table" then
			if finite(geo.Slab) and geo.Slab > 0 and geo.Slab <= 4 then
				SLAB = geo.Slab
			end
			if finite(geo.Core) and geo.Core >= 4 and geo.Core <= 20 then
				CORE = geo.Core
			end
			local fp = geo.Footprint
			if type(fp) == "table" and finite(fp.Small) and finite(fp.Large) and finite(fp.LargeFromStage) then
				SMALL, LARGE, LARGE_FROM = fp.Small, fp.Large, fp.LargeFromStage
			end
			if type(geo.Setbacks) == "table" then
				local list: { { number } } = {}
				for _, entry in ipairs(geo.Setbacks) do
					if type(entry) == "table" and finite(entry[1]) and finite(entry[2]) then
						table.insert(list, { entry[1], entry[2] })
					end
				end
				SETBACKS = list
			end
		end
		if type(towerCfg.Stages) == "table" and #towerCfg.Stages == 12 then
			local first: { number } = {}
			for i, stage in ipairs(towerCfg.Stages) do
				first[i] = if type(stage) == "table" and finite(stage.First) then stage.First else STAGE_FIRST[i]
			end
			STAGE_FIRST = first
		end
		if type(towerCfg.Rooms) == "table" then
			for _, room in ipairs(towerCfg.Rooms) do
				if type(room) == "table" and type(room.Key) == "string" and type(room.Code) == "string" then
					ROOM_CODE[room.Key] = room.Code
					if finite(room.DecorSlots) then
						ROOM_SLOTS[room.Key] = math.floor(room.DecorSlots)
					end
				end
			end
		end
		if type(towerCfg.Staff) == "table" then
			for _, staff in ipairs(towerCfg.Staff) do
				if type(staff) == "table" and type(staff.Key) == "string" and type(staff.Code) == "string" then
					STAFF_CODE[staff.Key] = staff.Code
				end
			end
		end
		if type(towerCfg.Neon) == "table" then
			for _, entry in ipairs(towerCfg.Neon) do
				if type(entry) == "table" and type(entry.Key) == "string" and isHex(entry.Hex) then
					NEON_HEX[entry.Key] = entry.Hex
				end
			end
		end
		if type(towerCfg.Crowns) == "table" then
			for _, entry in ipairs(towerCfg.Crowns) do
				if type(entry) == "table" and type(entry.Key) == "string" and isHex(entry.Hex) then
					CROWN_HEX[entry.Key] = entry.Hex
				end
			end
		end
	end
	if type(decorCfg) == "table" then
		if finite(decorCfg.SlotsPerFloor) then
			SLOTS_PER_FLOOR = math.clamp(math.floor(decorCfg.SlotsPerFloor), 1, 16)
		end
		if finite(decorCfg.PenthouseSlots) then
			PENTHOUSE_SLOTS = math.clamp(math.floor(decorCfg.PenthouseSlots), 1, 16)
			ROOM_SLOTS.Penthouse = PENTHOUSE_SLOTS
		end
		if type(decorCfg.Items) == "table" then
			for _, entry in ipairs(decorCfg.Items) do
				if type(entry) == "table" and type(entry.Key) == "string" and type(entry.Code) == "string" then
					DECOR_CODE[entry.Key] = entry.Code
				end
			end
		end
	end
	rebuildCodes()
end

function TowerModels.FloorHeight(): number
	return FH
end

function TowerModels.SlabHeight(): number
	return SLAB
end

-- ---------------------------------------------------------------------
-- 2) FARBEN (Hex-Text; rein rechnerisch, keine Color3)
-- ---------------------------------------------------------------------
function TowerModels.Hex(text: string): (number, number, number)
	if not isHex(text) then
		return 0, 0, 0
	end
	local r = tonumber(string.sub(text, 2, 3), 16) or 0
	local g = tonumber(string.sub(text, 4, 5), 16) or 0
	local b = tonumber(string.sub(text, 6, 7), 16) or 0
	return r, g, b
end

local function toHex(r: number, g: number, b: number): string
	local function c(v: number): number
		return math.clamp(math.floor(v + 0.5), 0, 255)
	end
	return string.format("#%02x%02x%02x", c(r), c(g), c(b))
end

-- a -> b mischen (t = 0 … 1)
local function mix(a: string, b: string, t: number): string
	local ar, ag, ab = TowerModels.Hex(a)
	local br, bg, bb = TowerModels.Hex(b)
	return toHex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

local function hsv(h: number, s: number, v: number): string
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b = v, t, p
	if i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	elseif i == 5 then
		r, g, b = v, p, q
	end
	return toHex(r * 255, g * 255, b * 255)
end

function TowerModels.NeonHex(key: string?): string
	return if type(key) == "string" and NEON_HEX[key] then NEON_HEX[key] else NEON_HEX.Accent
end

local function crownHex(key: string?): string?
	if type(key) == "string" and CROWN_HEX[key] then
		return CROWN_HEX[key]
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 3) FASSADEN-PALETTEN (§B4.9) – Code-Rezepte der 7 Fassaden
-- ---------------------------------------------------------------------
local SKINS: { [string]: Pal } = {
	GlassBlue = {
		Glass = "#3b6ea8",
		GlassT = 0.32,
		GlassR = 0.22,
		Frame = "#1f2937",
		FrameMat = "Metal",
		Slab = "#2a3342",
		SlabMat = "Concrete",
		Core = "#7fb2ff",
		Trim = "#4f8cff",
		Roof = "#1a2130",
		Accent = "#d7dee8",
	},
	Obsidian = {
		Glass = "#11131c",
		GlassT = 0.22,
		GlassR = 0.35,
		Frame = "#0b0f17",
		FrameMat = "Metal",
		Slab = "#141824",
		SlabMat = "Slate",
		Core = "#6d5dfc",
		Trim = "#7c5cff",
		Roof = "#0b0f17",
		Accent = "#7c5cff",
	},
	MarbleWhite = {
		Glass = "#9fbad6",
		GlassT = 0.35,
		GlassR = 0.18,
		Frame = "#e8ecf2",
		FrameMat = "Marble",
		Slab = "#f1f3f6",
		SlabMat = "Marble",
		Core = "#cfe0f5",
		Trim = "#c8a165",
		Roof = "#d9dde4",
		Accent = "#c8a165",
	},
	NeonCyber = {
		Glass = "#101a2c",
		GlassT = 0.28,
		GlassR = 0.3,
		Frame = "#121824",
		FrameMat = "Metal",
		Slab = "#151c2b",
		SlabMat = "DiamondPlate",
		Core = "#22d3ee",
		Trim = "#ec4899",
		Roof = "#0b0f17",
		Accent = "#22d3ee",
	},
	GoldLuxe = {
		Glass = "#5a4420",
		GlassT = 0.3,
		GlassR = 0.3,
		Frame = "#facc15",
		FrameMat = "Metal",
		Slab = "#2a2216",
		SlabMat = "Marble",
		Core = "#ffcf6e",
		Trim = "#facc15",
		Roof = "#1a1410",
		Accent = "#facc15",
	},
	HoloPrism = {
		Glass = "#7c9cff",
		GlassT = 0.3,
		GlassR = 0.28,
		Frame = "#d7dee8",
		FrameMat = "Metal",
		Slab = "#1f2533",
		SlabMat = "SmoothPlastic",
		Core = "#b36bff",
		Trim = "#7c5cff",
		Roof = "#1a2130",
		Accent = "#b36bff",
		Prism = true,
	},
	Polar = {
		Glass = "#cfe3f7",
		GlassT = 0.3,
		GlassR = 0.25,
		Frame = "#c0c7d4",
		FrameMat = "Metal",
		Slab = "#e6ecf5",
		SlabMat = "Concrete",
		Core = "#e0f2fe",
		Trim = "#93c5fd",
		Roof = "#d7dee8",
		Accent = "#93c5fd",
	},
}
local DEFAULT_SKIN = "GlassBlue"

-- Palette einer Fassade auf Etage floor (Holo-Prisma verschiebt den Farbton je Etage)
function TowerModels.Palette(skin: string?, floor: number?): Pal
	local base = SKINS[skin or ""] or SKINS[DEFAULT_SKIN]
	if base.Prism and floor then
		local copy = table.clone(base)
		copy.Glass = hsv((floor * 0.045) % 1, 0.45, 0.85)
		return copy
	end
	return base
end

function TowerModels.Skins(): { string }
	return { "GlassBlue", "Obsidian", "MarbleWhite", "NeonCyber", "GoldLuxe", "HoloPrism", "Polar" }
end

-- ---------------------------------------------------------------------
-- 4) SPEC-HELFER
-- ---------------------------------------------------------------------
local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

local function add(
	list: { PartSpec },
	size: { number },
	pos: { number },
	color: string,
	material: string,
	opts: Opts?
): PartSpec
	local spec: PartSpec = {
		Size = { r3(math.max(0.05, size[1])), r3(math.max(0.05, size[2])), r3(math.max(0.05, size[3])) },
		Pos = { r3(pos[1]), r3(pos[2]), r3(pos[3]) },
		Color = color,
		Material = material,
	}
	if opts then
		for key, value in pairs(opts) do
			(spec :: any)[key] = value
		end
	end
	table.insert(list, spec)
	return spec
end

local function G(x: number, y: number, z: number, yaw: number?): Group
	local deg = yaw or 0
	local rad = math.rad(deg)
	return { X = x, Y = y, Z = z, Yaw = deg, C = math.cos(rad), S = math.sin(rad) }
end

-- Teil relativ zu einer Gruppe (Versatz ox/oy/oz wird um die Gruppen-Gierachse gedreht)
local function put(
	list: { PartSpec },
	g: Group,
	size: { number },
	ox: number,
	oy: number,
	oz: number,
	color: string,
	material: string,
	opts: Opts?
): PartSpec
	local x = g.X + g.C * ox + g.S * oz
	local z = g.Z - g.S * ox + g.C * oz
	local o: Opts = {}
	if opts then
		for key, value in pairs(opts) do
			o[key] = value
		end
	end
	local rot = o.Rot
	if g.Yaw ~= 0 or rot ~= nil then
		local rx = if type(rot) == "table" then rot[1] or 0 else 0
		local ry = if type(rot) == "table" then rot[2] or 0 else 0
		local rz = if type(rot) == "table" then rot[3] or 0 else 0
		o.Rot = { r3(rx), r3((ry + g.Yaw) % 360), r3(rz) }
	end
	return add(list, size, { x, g.Y + oy, z }, color, material, o)
end

local VERTICAL = { 0, 0, 90 } -- Zylinder senkrecht stellen (Achse X -> Y)

local function clampStage(stage: any): number
	return if finite(stage) then math.clamp(math.floor(stage), 1, 12) else 1
end

local function clampFloor(floor: any): number
	return if finite(floor) then math.clamp(math.floor(floor), 1, FLOORS) else 1
end

-- ---------------------------------------------------------------------
-- 5) GRUNDRISS & STUFEN (§B4.1, §B4.2)
-- ---------------------------------------------------------------------
function TowerModels.StageOf(floors: number): number
	if not finite(floors) or floors < 1 then
		return 1
	end
	local stage = 1
	for i, first in ipairs(STAGE_FIRST) do
		if floors >= first then
			stage = i
		end
	end
	return stage
end

function TowerModels.Footprint(stage: number, floor: number): number
	local s = clampStage(stage)
	local f = clampFloor(floor)
	local size = if s >= LARGE_FROM then LARGE else SMALL
	if s >= LARGE_FROM then
		for _, setback in ipairs(SETBACKS) do
			if f >= setback[1] then
				size = math.min(size, setback[2])
			end
		end
	end
	return size
end

-- Abschnitte gleichen Grundrisses: { { first, last, size } }
local function segments(stage: number, floors: number): { { number } }
	local list: { { number } } = {}
	local current: { number }? = nil
	for f = 1, floors do
		local size = TowerModels.Footprint(stage, f)
		if current and current[3] == size then
			current[2] = f
		else
			current = { f, f, size }
			table.insert(list, current :: { number })
		end
	end
	return list
end

-- Aussehen je Stufe: Deckenplatte (nach unten verlängert = Fensterband), Vorhangfassade, Neonband
type Look = { Down: number, Grow: number, Curtain: boolean, Band: boolean, Wall: string }
local function lookOf(stage: number): Look
	if stage <= 2 then
		return { Down = 0, Grow = 0, Curtain = false, Band = false, Wall = "Plaster" }
	elseif stage == 3 then
		return { Down = 0, Grow = 0.3, Curtain = false, Band = false, Wall = "Brick" }
	elseif stage == 4 then
		return { Down = 2, Grow = 0.4, Curtain = false, Band = true, Wall = "Band" }
	end
	return { Down = 0.4, Grow = -0.8, Curtain = true, Band = true, Wall = "Glass" }
end

-- ---------------------------------------------------------------------
-- 6) HÜLLE EINER ETAGE (≤ 8 Parts: Platte, 4 Fassaden (EG vorn mit Tür = 3), Neonband, Stufen-Extras)
-- ---------------------------------------------------------------------
function TowerModels.Shell(stage: number, floor: number, skin: string, neon: string): { PartSpec }
	local s = clampStage(stage)
	local n = clampFloor(floor)
	local list: { PartSpec } = {}
	local pal = TowerModels.Palette(skin, n)
	local neonHex = TowerModels.NeonHex(neon)
	local look = lookOf(s)
	local size = TowerModels.Footprint(s, n)
	local half = size / 2
	local y0 = (n - 1) * FH
	local floorAttr = { Floor = n }

	-- 1) Deckenplatte (bei Fensterbändern nach unten verlängert, im EG nie unter den Boden)
	local down = if n == 1 then 0 else look.Down
	local slabSize = size + look.Grow
	local slabColor = if look.Wall == "Band" then mix(pal.Slab, "#e6ecf5", 0.75) else pal.Slab
	local slabMat = if look.Wall == "Band" then "Concrete" else pal.SlabMat
	if s <= 2 then
		slabColor, slabMat = "#5b5f66", "Concrete"
	elseif s == 3 then
		slabColor, slabMat = "#3a3f47", "Concrete"
	end
	add(list, { slabSize, SLAB + down, slabSize }, { 0, y0 + (SLAB - down) / 2, 0 }, slabColor, slabMat, {
		Tag = "Slab",
		Collide = true,
		Query = true,
		Attr = floorAttr,
	})

	-- 2) Fassaden-Material je Stufe
	local glassColor, glassT, glassR = pal.Glass, pal.GlassT, pal.GlassR
	local wallColor, wallMat = "#c9d2de", "SmoothPlastic"
	if s == 1 then
		wallColor, wallMat = "#7a4a35", "Brick"
	elseif s == 2 then
		wallColor, wallMat = mix("#c9d2de", pal.Trim, 0.08), "Plaster"
	elseif s == 3 then
		wallColor, wallMat = "#8a4b32", "Brick"
	end
	local bottom = if look.Curtain then y0 else y0 + SLAB
	local height = (y0 + FH) - bottom
	local midY = bottom + height / 2
	local off = if look.Curtain then half + 0.2 else half - 0.2
	local thick = 0.4

	local function glass(sz: { number }, pos: { number }, side: string)
		add(list, sz, pos, glassColor, "Glass", {
			Tag = "Facade",
			Transparency = glassT,
			Reflectance = glassR,
			Collide = true,
			Query = true,
			Shadow = false,
			Attr = { Floor = n, Side = side },
		})
	end
	local function wall(sz: { number }, pos: { number }, side: string)
		add(list, sz, pos, wallColor, wallMat, {
			Tag = "Facade",
			Collide = true,
			Query = true,
			Attr = { Floor = n, Side = side },
		})
	end

	-- Seiten und Rückseite
	local sideIsWall = s == 1 or s == 2 or s == 3
	local backIsWall = s == 1 or (s == 2 and n > 1)
	if sideIsWall then
		wall({ thick, height, size }, { -off, midY, 0 }, "Left")
		wall({ thick, height, size }, { off, midY, 0 }, "Right")
	else
		glass({ thick, height, size }, { -off, midY, 0 }, "Left")
		glass({ thick, height, size }, { off, midY, 0 }, "Right")
	end
	if backIsWall then
		wall({ size, height, thick }, { 0, midY, off }, "Back")
	else
		glass({ size, height, thick }, { 0, midY, off }, "Back")
	end

	-- Vorderseite: EG mit Eingang (Stufe 1: hochgerolltes Garagentor), sonst ein Feld
	if n == 1 and s == 1 then
		local doorW = 14
		local panelW = (size - doorW) / 2
		wall({ panelW, height, thick }, { -(doorW / 2 + panelW / 2), midY, -off }, "Front")
		wall({ panelW, height, thick }, { doorW / 2 + panelW / 2, midY, -off }, "Front")
		-- Rolltor halb offen (Durchgang darunter), Blende darüber
		add(list, { doorW, 5, 0.5 }, { 0, 8.5, -off - 0.1 }, "#8b97a8", "CorrodedMetal", {
			Tag = "RollerDoor",
			Collide = true,
			Query = true,
			Attr = floorAttr,
		})
		add(list, { doorW + 1, 1.2, 0.8 }, { 0, 11.4, -off - 0.2 }, pal.Trim, "Metal", {
			Tag = "Trim",
			Collide = false,
			Attr = floorAttr,
		})
	elseif n == 1 then
		local panelW = (size - DOOR_W) / 2
		local doorTop = DOOR_TOP
		local transH = (y0 + FH) - doorTop
		local frontColor = if s == 3 then wallColor else glassColor
		local function front(sz: { number }, pos: { number })
			if s == 3 then
				wall(sz, pos, "Front")
			else
				glass(sz, pos, "Front")
			end
		end
		front({ panelW, height, thick }, { -(DOOR_W / 2 + panelW / 2), midY, -off })
		front({ panelW, height, thick }, { DOOR_W / 2 + panelW / 2, midY, -off })
		add(list, { DOOR_W, transH, thick }, { 0, doorTop + transH / 2, -off }, frontColor, "Glass", {
			Tag = "Facade",
			Transparency = glassT,
			Reflectance = glassR,
			Collide = true,
			Query = true,
			Attr = { Floor = n, Side = "Front" },
		})
		if s == 2 then
			-- Markise über dem Kiosk-Eingang
			add(list, { size * 0.8, 1.6, 4 }, { 0, 10, -off - 2.2 }, pal.Trim, "Fabric", {
				Kind = "Wedge",
				Tag = "Awning",
				Collide = false,
				Attr = floorAttr,
			})
		end
	else
		glass({ size, height, thick }, { 0, midY, -off }, "Front")
	end

	-- 3) Neonband (Fensterlicht-Streifen nachts, Stufe 4+)
	if look.Band then
		local bandSize = size + (if look.Curtain then 1.4 else 0.9)
		local bandY = if n == 1 then 0.6 else y0 + 0.5
		add(list, { bandSize, 0.3, bandSize }, { 0, bandY, 0 }, neonHex, "Neon", {
			Tag = "Neon",
			Collide = false,
			Shadow = false,
			Attr = floorAttr,
		})
	end

	-- 4) Holo-Bänder (Hyper-Spire alle 6, Orbit-Spire alle 4 Etagen)
	if (s == 11 and n % 6 == 0) or (s == 12 and n % 4 == 0) then
		add(list, { size + 3, 0.6, size + 3 }, { 0, y0 + 6, 0 }, if s == 12 then "#b36bff" else "#7c9cff", "Neon", {
			Tag = "Holo",
			Transparency = 0.55,
			Collide = false,
			Shadow = false,
			Attr = floorAttr,
		})
	end
	return list
end

-- ---------------------------------------------------------------------
-- 7) SENKRECHTE TEILE (Ecksäulen je Grundriss-Abschnitt, Aufzugskern, Neon-Finnen)
-- ---------------------------------------------------------------------
function TowerModels.Spine(stage: number, floors: number, skin: string, neon: string): { PartSpec }
	local s = clampStage(stage)
	local list: { PartSpec } = {}
	local count = if finite(floors) then math.clamp(math.floor(floors), 0, FLOORS) else 0
	if count <= 0 then
		return list
	end
	local pal = TowerModels.Palette(skin, nil)
	local neonHex = TowerModels.NeonHex(neon)
	local look = lookOf(s)
	local pillarColor = if s <= 3 then "#3a3f47" else pal.Frame
	local pillarMat = if s <= 3 then "Concrete" else pal.FrameMat
	for _, seg in ipairs(segments(s, count)) do
		local first, last, size = seg[1], seg[2], seg[3]
		local bottom = (first - 1) * FH
		local top = last * FH
		local h = top - bottom
		local c = if look.Curtain then size / 2 + 0.2 else size / 2
		local w = if look.Curtain then 1.0 else 1.4
		for _, sign in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			add(list, { w, h, w }, { sign[1] * c, bottom + h / 2, sign[2] * c }, pillarColor, pillarMat, {
				Tag = "Pillar",
				Collide = true,
				Query = true,
				Attr = { First = first, Last = last },
			})
		end
	end
	if count >= 2 then
		local h = count * FH - SLAB
		add(list, { CORE, h, CORE }, { 0, SLAB + h / 2, 0 }, pal.Core, "Glass", {
			Tag = "Core",
			Transparency = 0.55,
			Reflectance = 0.15,
			Collide = true,
			Query = true,
			Shadow = false,
		})
	end
	-- Neon-Finnen: Hochhaus/Wolkenkratzer 2 je Seite, Skyline/Mega 1 kräftige je Seite
	if s >= 7 and s <= 10 then
		local size = TowerModels.Footprint(s, 1)
		local reach = size / 2 + 0.7
		local h = math.min(count, 30) * FH - SLAB
		local y = SLAB + h / 2
		local offsets = if s <= 8 then { -size * 0.25, size * 0.25 } else { 0 }
		local fin = if s <= 8 then 0.45 else 0.9
		for _, o in ipairs(offsets) do
			add(list, { fin, h, 0.8 }, { o, y, -reach }, neonHex, "Neon", { Tag = "Fin", Shadow = false })
			add(list, { fin, h, 0.8 }, { o, y, reach }, neonHex, "Neon", { Tag = "Fin", Shadow = false })
			add(list, { 0.8, h, fin }, { -reach, y, o }, neonHex, "Neon", { Tag = "Fin", Shadow = false })
			add(list, { 0.8, h, fin }, { reach, y, o }, neonHex, "Neon", { Tag = "Fin", Shadow = false })
		end
	end
	return list
end

-- ---------------------------------------------------------------------
-- 8) DACH & KRONE (Dach-lokal; ≤ 60 Parts inkl. Börsengang-Krone)
-- ---------------------------------------------------------------------
-- Höhe der Börsengang-Krone über dem Dach je Stufe
local CROWN_TOP: { number } = { 6, 6, 7, 6, 8, 15, 28, 18, 40, 10, 34, 46 }

local function ipoCrown(list: { PartSpec }, crown: string?, topY: number)
	local hex = crownHex(crown)
	if not hex then
		return
	end
	local count = if crown == "Silver" then 6 elseif crown == "Gold" then 8 else 10
	local radius = 5
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2
		add(list, { 1.1, 1.1, 1.1 }, { math.cos(a) * radius, topY, math.sin(a) * radius }, hex, "Neon", {
			Shape = "Ball",
			Tag = "IpoCrown",
			Group = "IpoCrown",
			Anim = "Spin",
			Shadow = false,
		})
	end
	add(list, { 0.4, radius * 2 + 1, radius * 2 + 1 }, { 0, topY, 0 }, hex, "Metal", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "IpoCrown",
		Transparency = 0.2,
		Shadow = false,
	})
	if crown == "Holo" or crown == "Orbit" then
		add(list, { 0.25, radius * 3, radius * 3 }, { 0, topY + 1.5, 0 }, hex, "Neon", {
			Shape = "Cylinder",
			Rot = { 0, 0, 72 },
			Tag = "IpoCrown",
			Transparency = 0.45,
			Group = "IpoRing",
			Anim = "Spin",
			Shadow = false,
		})
	end
	if crown == "Orbit" then
		add(list, { 0.25, radius * 3.8, radius * 3.8 }, { 0, topY + 2.5, 0 }, hex, "Neon", {
			Shape = "Cylinder",
			Rot = { 0, 60, 108 },
			Tag = "IpoCrown",
			Transparency = 0.5,
			Group = "IpoRing2",
			Anim = "Spin",
			Shadow = false,
		})
	end
end

local function roof(list: { PartSpec }, size: number, color: string, material: string)
	add(list, { size, SLAB, size }, { 0, SLAB / 2, 0 }, color, material, {
		Tag = "Roof",
		Collide = true,
		Query = true,
	})
end

local function parapet(list: { PartSpec }, size: number, h: number, color: string, material: string, t: number?)
	local half = size / 2
	local o: Opts = { Tag = "Parapet", Collide = true, Query = true, Transparency = t or 0 }
	add(list, { size, h, 0.6 }, { 0, SLAB + h / 2, -half + 0.3 }, color, material, o)
	add(list, { size, h, 0.6 }, { 0, SLAB + h / 2, half - 0.3 }, color, material, o)
	add(list, { 0.6, h, size - 1.2 }, { -half + 0.3, SLAB + h / 2, 0 }, color, material, o)
	add(list, { 0.6, h, size - 1.2 }, { half - 0.3, SLAB + h / 2, 0 }, color, material, o)
end

local function tree(list: { PartSpec }, x: number, z: number, y: number, crownColor: string, scale: number)
	add(list, { 3 * scale, 0.6 * scale, 0.6 * scale }, { x, y + 1.5 * scale, z }, "#5b3a24", "Wood", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "Tree",
	})
	add(list, { 2.6 * scale, 2.6 * scale, 2.6 * scale }, { x, y + 3.6 * scale, z }, crownColor, "Grass", {
		Shape = "Ball",
		Tag = "Tree",
	})
end

function TowerModels.Crown(stage: number, crown: string, floors: number?, skin: string?, neon: string?): { PartSpec }
	local s = clampStage(stage)
	local list: { PartSpec } = {}
	local top = if finite(floors) and (floors :: number) >= 1
		then clampFloor(floors)
		else (STAGE_FIRST[s + 1] or 51) - 1
	top = math.max(1, math.min(top, FLOORS))
	local size = TowerModels.Footprint(s, top)
	local half = size / 2
	local pal = TowerModels.Palette(skin or DEFAULT_SKIN, top)
	local neonHex = TowerModels.NeonHex(neon)
	local accent = crownHex(crown) or neonHex
	local noShadow: Opts = { Shadow = false }

	if s == 1 then
		roof(list, size, "#4a4f57", "Concrete")
		add(list, { 16, 3.5, 0.5 }, { 0, SLAB + 1.75, -half + 0.6 }, "#121824", "Metal", {
			Tag = "Sign",
			Attr = { Sign = "Startup", Face = "Front" },
		})
		add(list, { 16.6, 0.25, 0.3 }, { 0, SLAB + 3.6, -half + 0.35 }, neonHex, "Neon", noShadow)
		add(list, { 4, 2, 3 }, { half * 0.5, SLAB + 1, half * 0.4 }, "#8b97a8", "Metal", { Tag = "Vent" })
	elseif s == 2 then
		roof(list, size, "#4a4f57", "Concrete")
		add(list, { size, 1.2, 0.6 }, { 0, SLAB + 0.6, -half + 0.3 }, mix("#c9d2de", pal.Trim, 0.15), "Plaster", {
			Tag = "Parapet",
			Collide = true,
		})
		add(list, { size * 0.6, 0.3, 0.3 }, { 0, SLAB + 1.35, -half + 0.2 }, neonHex, "Neon", noShadow)
		add(list, { 4, 2, 3 }, { -half * 0.4, SLAB + 1, half * 0.3 }, "#8b97a8", "Metal", { Tag = "Vent" })
		add(list, { 3, 1.6, 3 }, { half * 0.45, SLAB + 0.8, half * 0.5 }, "#8b97a8", "Metal", { Tag = "Vent" })
	elseif s == 3 then
		-- Dachterrasse: Holzdeck, Glasgeländer, Liegestühle, Schirm, Pflanzen, Lichterkette
		roof(list, size, "#8a6a4a", "WoodPlanks")
		parapet(list, size, 1.4, "#cfe3f7", "Glass", 0.55)
		for _, x in ipairs({ -6, -1 }) do
			add(list, { 2.4, 0.6, 5 }, { x, SLAB + 0.3, -half * 0.35 }, "#e6ecf5", "Fabric", { Tag = "Deck" })
			add(list, { 2.4, 2, 1.2 }, { x, SLAB + 1.2, -half * 0.35 + 2.4 }, "#e6ecf5", "Fabric", {
				Kind = "Wedge",
				Tag = "Deck",
			})
		end
		add(list, { 6, 0.3, 0.3 }, { half * 0.45, SLAB + 3, -half * 0.35 }, "#c9d2de", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Umbrella",
		})
		add(list, { 0.5, 7, 7 }, { half * 0.45, SLAB + 6, -half * 0.35 }, pal.Trim, "Fabric", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Umbrella",
		})
		add(list, { 3, 1.2, 3 }, { -half * 0.6, SLAB + 0.6, half * 0.55 }, "#5b5f66", "Concrete", { Tag = "Planter" })
		add(list, { 2.6, 2.6, 2.6 }, { -half * 0.6, SLAB + 2.3, half * 0.55 }, "#3f8f3a", "Grass", {
			Shape = "Ball",
			Tag = "Planter",
		})
		add(list, { size - 2, 0.15, 0.15 }, { 0, SLAB + 2.4, half * 0.1 }, "#ffd9a0", "Neon", {
			Tag = "StringLights",
			Shadow = false,
		})
	elseif s == 4 then
		roof(list, size, pal.Roof, "Concrete")
		parapet(list, size, 1, mix(pal.Slab, "#e6ecf5", 0.75), "Concrete")
		add(list, { 5, 2.4, 4 }, { -half * 0.45, SLAB + 1.2, half * 0.4 }, "#8b97a8", "Metal", { Tag = "Vent" })
		add(list, { 4, 2, 4 }, { half * 0.4, SLAB + 1, half * 0.45 }, "#8b97a8", "Metal", { Tag = "Vent" })
		add(list, { 4, 4, 4 }, { half * 0.5, SLAB + 2, -half * 0.4 }, "#7d889a", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Tank",
		})
		add(list, { size + 0.8, 0.35, size + 0.8 }, { 0, SLAB + 1.1, 0 }, neonHex, "Neon", {
			Tag = "Neon",
			Transparency = 0.1,
			Shadow = false,
		})
	elseif s == 5 then
		roof(list, size, pal.Roof, "Concrete")
		parapet(list, size, 2.2, pal.Glass, "Glass", pal.GlassT)
		for _, p in ipairs({ { -1, -1 }, { 1, 1 } }) do
			local x, z = p[1] * half * 0.45, p[2] * half * 0.45
			add(list, { 6, 1.2, 6 }, { x, SLAB + 0.6, z }, "#3a3f47", "Concrete", { Tag = "Planter" })
			tree(list, x, z, SLAB + 1.2, "#3f8f3a", 1)
		end
		add(list, { 12, 0.5, 0.5 }, { half * 0.5, SLAB + 6, -half * 0.5 }, "#c0c7d4", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Antenna",
		})
	elseif s == 6 then
		-- abgetreppte Krone + Dach-LED
		roof(list, size, pal.Roof, "Concrete")
		local y = SLAB
		for i, f in ipairs({ 0.8, 0.6, 0.4 }) do
			local w = size * f
			add(list, { w, 4, w }, { 0, y + 2, 0 }, pal.Glass, "Glass", {
				Tag = "Tier",
				Transparency = pal.GlassT,
				Reflectance = pal.GlassR,
				Collide = true,
			})
			add(list, { w + 0.6, 0.3, w + 0.6 }, { 0, y + 4, 0 }, if i == 3 then accent else neonHex, "Neon", noShadow)
			y += 4
		end
		add(list, { size * 0.6, 3, 0.3 }, { 0, SLAB + 2, -size * 0.4 - 0.35 }, "#0b0f17", "SmoothPlastic", {
			Tag = "Led",
			Attr = { Led = true, Face = "Front" },
		})
	elseif s == 7 then
		roof(list, size, pal.Roof, "Concrete")
		local w = size * 0.7
		add(list, { w, 6, w }, { 0, SLAB + 3, 0 }, pal.Glass, "Glass", {
			Tag = "Tier",
			Transparency = pal.GlassT,
			Reflectance = pal.GlassR,
			Collide = true,
		})
		for _, p in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			add(list, { 0.6, 8, 0.6 }, { p[1] * w / 2, SLAB + 4, p[2] * w / 2 }, neonHex, "Neon", noShadow)
		end
		add(list, { 20, 0.8, 0.8 }, { 0, SLAB + 6 + 10, 0 }, "#c0c7d4", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Antenna",
		})
		add(list, { 1.4, 1.4, 1.4 }, { 0, SLAB + 26.5, 0 }, "#ef4444", "Neon", {
			Shape = "Ball",
			Tag = "Beacon",
			Anim = "Beacon",
			Shadow = false,
		})
	elseif s == 8 then
		-- Zwillingskrone + Himmelsbrücke + LED-Fassaden-Ticker (AKX36-Farbe, nie eigenes G/V)
		roof(list, size, pal.Roof, "Concrete")
		local w = size * 0.3
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * size * 0.22
			add(list, { w, 14, w }, { x, SLAB + 7, 0 }, pal.Glass, "Glass", {
				Tag = "Twin",
				Transparency = pal.GlassT,
				Reflectance = pal.GlassR,
				Collide = true,
			})
			add(
				list,
				{ w, 5, w / 2 },
				{ x, SLAB + 16.5, -w / 4 },
				pal.Frame,
				pal.FrameMat,
				{ Kind = "Wedge", Tag = "Twin" }
			)
			add(list, { w, 5, w / 2 }, { x, SLAB + 16.5, w / 4 }, pal.Frame, pal.FrameMat, {
				Kind = "Wedge",
				Rot = { 0, 180, 0 },
				Tag = "Twin",
			})
			add(list, { w + 0.5, 0.3, w + 0.5 }, { x, SLAB + 14, 0 }, accent, "Neon", noShadow)
		end
		add(list, { size * 0.44 - w, 2, 4 }, { 0, SLAB + 9, 0 }, pal.Glass, "Glass", {
			Tag = "Bridge",
			Transparency = 0.2,
		})
		local ledY = -3.5
		add(list, { size + 0.6, 2.5, 0.3 }, { 0, ledY, -half - 0.55 }, "#0b0f17", "SmoothPlastic", {
			Tag = "Led",
			Attr = { Led = true, Face = "Front" },
		})
		add(list, { size + 0.6, 2.5, 0.3 }, { 0, ledY, half + 0.55 }, "#0b0f17", "SmoothPlastic", {
			Tag = "Led",
			Attr = { Led = true, Face = "Back" },
		})
		add(list, { 0.3, 2.5, size + 0.6 }, { -half - 0.55, ledY, 0 }, "#0b0f17", "SmoothPlastic", {
			Tag = "Led",
			Attr = { Led = true, Face = "Left" },
		})
		add(list, { 0.3, 2.5, size + 0.6 }, { half + 0.55, ledY, 0 }, "#0b0f17", "SmoothPlastic", {
			Tag = "Led",
			Attr = { Led = true, Face = "Right" },
		})
	elseif s == 9 then
		-- beleuchtete Turmspitze + Himmelsgarten
		roof(list, size, "#2f6b3a", "Grass")
		add(list, { 6, 10, 10 }, { 0, SLAB + 3, 0 }, pal.Frame, pal.FrameMat, {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Spire",
		})
		add(list, { 14, 6, 6 }, { 0, SLAB + 13, 0 }, neonHex, "Neon", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Spire",
			Transparency = 0.25,
			Shadow = false,
		})
		add(list, { 20, 1.6, 1.6 }, { 0, SLAB + 30, 0 }, "#e6ecf5", "Neon", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Spire",
			Shadow = false,
		})
		for i = 1, 4 do
			local a = (i - 0.5) / 4 * math.pi * 2
			local x, z = math.cos(a) * half * 0.62, math.sin(a) * half * 0.62
			tree(list, x, z, SLAB, if i % 2 == 0 then "#3f8f3a" else "#2f9e5b", 1.3)
			add(list, { 0.6, 0.6, 0.6 }, { x * 0.7, SLAB + 0.5, z * 0.7 }, "#ffd9a0", "Neon", {
				Shape = "Ball",
				Tag = "GardenLight",
				Shadow = false,
			})
		end
		add(
			list,
			{ size - 4, 0.6, size - 4 },
			{ 0, SLAB + 0.3, 0 },
			"#8a6a4a",
			"WoodPlanks",
			{ Tag = "Deck", Collide = true }
		)
	elseif s == 10 then
		-- Helipad, Leuchtfeuer, Suchscheinwerfer
		roof(list, size, pal.Roof, "Concrete")
		local pad = size * 0.72
		add(list, { 1, pad, pad }, { 0, SLAB + 0.5, 0 }, "#2a3342", "Concrete", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Helipad",
			Collide = true,
			Query = true,
		})
		add(list, { 1.2, 0.12, 9 }, { -3, SLAB + 1.06, 0 }, "#facc15", "Neon", { Tag = "Helipad", Shadow = false })
		add(list, { 1.2, 0.12, 9 }, { 3, SLAB + 1.06, 0 }, "#facc15", "Neon", { Tag = "Helipad", Shadow = false })
		add(list, { 6, 0.12, 1.2 }, { 0, SLAB + 1.06, 0 }, "#facc15", "Neon", { Tag = "Helipad", Shadow = false })
		for i = 1, 8 do
			local a = (i - 1) / 8 * math.pi * 2
			add(
				list,
				{ 0.6, 0.4, 0.6 },
				{ math.cos(a) * pad * 0.47, SLAB + 1.2, math.sin(a) * pad * 0.47 },
				"#22c55e",
				"Neon",
				{
					Tag = "PadLight",
					Shadow = false,
				}
			)
		end
		add(list, { 6, 0.6, 0.6 }, { half - 2, SLAB + 3, half - 2 }, "#c0c7d4", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Beacon",
		})
		add(list, { 1.6, 1.6, 1.6 }, { half - 2, SLAB + 6.6, half - 2 }, "#ef4444", "Neon", {
			Shape = "Ball",
			Tag = "Beacon",
			Anim = "Beacon",
			Shadow = false,
		})
		for i, sx in ipairs({ -1, 1 }) do
			local x, z = sx * (half - 2.5), -(half - 2.5)
			add(list, { 1.6, 1.4, 1.6 }, { x, SLAB + 0.7, z }, "#1f2937", "Metal", { Tag = "Searchlight" })
			add(list, { 1.2, 1.2, 2.4 }, { x, SLAB + 2, z }, "#e6ecf5", "Metal", {
				Tag = "Searchlight",
				Group = "Search" .. i,
				Anim = "Sweep",
				Rot = { 35, 0, 0 },
				Light = { Kind = "Spot", Range = 60, Brightness = 3, Color = "#e6f0ff", Face = "Front", Angle = 18 },
			})
		end
	elseif s == 11 then
		-- Sky-Lounge-Ring + Holo-Bänder
		roof(list, size, pal.Roof, "Concrete")
		add(list, { 8, size * 0.55, size * 0.55 }, { 0, SLAB + 4, 0 }, pal.Glass, "Glass", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Lounge",
			Transparency = pal.GlassT,
			Reflectance = pal.GlassR,
			Collide = true,
		})
		add(list, { 1, size * 0.95, size * 0.95 }, { 0, SLAB + 8.5, 0 }, pal.Frame, pal.FrameMat, {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Lounge",
			Collide = true,
		})
		add(list, { 0.3, size * 0.97, size * 0.97 }, { 0, SLAB + 9.2, 0 }, neonHex, "Neon", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Lounge",
			Transparency = 0.3,
			Shadow = false,
		})
		for i, d in ipairs({ 0.8, 0.6, 0.4 }) do
			add(list, { 0.4, size * d, size * d }, { 0, SLAB + 12 + i * 5, 0 }, "#7c9cff", "Neon", {
				Shape = "Cylinder",
				Rot = VERTICAL,
				Tag = "Holo",
				Transparency = 0.5,
				Group = "Holo" .. i,
				Anim = "Bob",
				Shadow = false,
			})
		end
		add(list, { 22, 1.2, 1.2 }, { 0, SLAB + 20, 0 }, "#c0c7d4", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Antenna",
		})
		add(list, { 1.4, 1.4, 1.4 }, { 0, SLAB + 31.5, 0 }, "#ef4444", "Neon", {
			Shape = "Ball",
			Tag = "Beacon",
			Anim = "Beacon",
			Shadow = false,
		})
	else
		-- ΛKYTEX Orbit-Spire: Antennen-Beam in die Wolken, Holo-Krone mit ΛKYTEX-Ring
		roof(list, size, pal.Roof, "Concrete")
		add(list, { 6, size * 0.5, size * 0.5 }, { 0, SLAB + 3, 0 }, pal.Frame, pal.FrameMat, {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Drum",
			Collide = true,
		})
		add(list, { 60, 1.6, 1.6 }, { 0, SLAB + 36, 0 }, "#d7dee8", "Metal", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Antenna",
		})
		add(list, { 72, 0.8, 0.8 }, { 0, SLAB + 42, 0 }, "#b36bff", "Neon", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Tag = "Beam",
			Attr = { Beam = true },
			Transparency = 0.35,
			Shadow = false,
		})
		local ringR = size * 0.32
		for i = 1, 12 do
			local a = (i - 1) / 12 * math.pi * 2
			add(
				list,
				{ 2.2, 0.5, ringR * 0.5 },
				{ math.cos(a) * ringR, SLAB + 20, math.sin(a) * ringR },
				"#7c5cff",
				"Neon",
				{
					Rot = { 0, -math.deg(a), 0 },
					Tag = "HoloCrown",
					Group = "OrbitRing",
					Anim = "Spin",
					Transparency = 0.2,
					Shadow = false,
				}
			)
		end
		-- Λ aus zwei geneigten Neon-Balken (Logo-Striche), schwebend über dem Ring
		add(list, { 0.8, 9, 0.8 }, { -1.6, SLAB + 26, 0 }, "#eaf1ff", "Neon", {
			Rot = { 0, 0, -20 },
			Tag = "Lambda",
			Group = "Lambda",
			Anim = "Spin",
			Shadow = false,
		})
		add(list, { 0.8, 9, 0.8 }, { 1.6, SLAB + 26, 0 }, "#eaf1ff", "Neon", {
			Rot = { 0, 0, 20 },
			Tag = "Lambda",
			Group = "Lambda",
			Anim = "Spin",
			Shadow = false,
		})
		for i = 1, 4 do
			local a = (i - 1) / 4 * math.pi * 2
			add(
				list,
				{ 1, 1, 1 },
				{ math.cos(a) * (ringR + 4), SLAB + 22, math.sin(a) * (ringR + 4) },
				"#6ea2f2",
				"Neon",
				{
					Shape = "Ball",
					Tag = "Orbit",
					Group = "OrbitDots",
					Anim = "Spin",
					Shadow = false,
				}
			)
		end
	end
	ipoCrown(list, crown, SLAB + (CROWN_TOP[s] or 8))
	return list
end

-- ---------------------------------------------------------------------
-- 9) PLOT-AUSSTATTUNG (≤ 40 Parts): Tresor, Kassen-Tor, Schild, Respekt-Säule, Eingang, Lobby, Garagentor
-- ---------------------------------------------------------------------
function TowerModels.Site(stage: number, floors: number, skin: string, neon: string): { PartSpec }
	local s = clampStage(stage)
	local count = if finite(floors) then math.clamp(math.floor(floors), 0, FLOORS) else 0
	local list: { PartSpec } = {}
	local pal = TowerModels.Palette(skin, 1)
	local neonHex = TowerModels.NeonHex(neon)
	local size = TowerModels.Footprint(s, 1)
	local half = size / 2
	local inner = half - 1.4 -- Innen-Halbbreite (gleiche Rechnung wie die Interiors)
	local front = -half
	local gold, goldMat = "#facc15", "Metal"

	-- Kassen-Tor (goldenes Tor auf dem Vorplatz, Durchgang = einsammeln)
	local gateZ = front - 10
	add(list, { 1.2, 10, 1.2 }, { -4.6, 5, gateZ }, gold, goldMat, { Tag = "CashGate", Collide = true, Query = true })
	add(list, { 1.2, 10, 1.2 }, { 4.6, 5, gateZ }, gold, goldMat, { Tag = "CashGate", Collide = true, Query = true })
	add(list, { 10.6, 1.4, 1.6 }, { 0, 10.4, gateZ }, gold, goldMat, { Tag = "CashGate" })
	add(list, { 8, 9, 0.2 }, { 0, 4.8, gateZ }, "#ffcf6e", "Neon", {
		Tag = "CashGate",
		Transparency = 0.75,
		Shadow = false,
		Attr = { CashGate = true },
	})
	-- Plot-Schild (Name, Tower-Name, Lizenz, Titel – Text baut der Client lokalisiert)
	add(list, { 0.6, 6, 0.6 }, { -half * 0.75, 3, front - 6 }, "#1f2937", "Metal", { Tag = "Sign", Collide = true })
	add(list, { 9, 4, 0.5 }, { -half * 0.75, 6.5, front - 6 }, "#121824", "SmoothPlastic", {
		Tag = "Sign",
		Collide = true,
		Attr = { PlotSign = true, Face = "Front" },
	})
	-- Respekt-Säule
	add(list, { 3, 1, 3 }, { half * 0.75, 0.5, front - 6 }, "#2a3342", "Marble", { Tag = "Respekt", Collide = true })
	add(list, { 7, 1.6, 1.6 }, { half * 0.75, 4.5, front - 6 }, "#cfe3f7", "Glass", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "Respekt",
		Transparency = 0.35,
		Collide = true,
	})
	add(list, { 0.4, 2.6, 2.6 }, { half * 0.75, 8.2, front - 6 }, gold, "Neon", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "Respekt",
		Shadow = false,
		Attr = { Respekt = true },
	})

	if count <= 0 then
		-- Bauplatz: Bauzaun + kleine Garage mit Rolltor (§B4.2 „0 Etagen“)
		local fence = size + 4
		local fh = 3
		local fo: Opts = { Tag = "Fence", Transparency = 0.2, Collide = true }
		add(list, { fence, fh, 0.3 }, { 0, fh / 2, -fence / 2 }, "#f59e0b", "DiamondPlate", fo)
		add(list, { fence, fh, 0.3 }, { 0, fh / 2, fence / 2 }, "#f59e0b", "DiamondPlate", fo)
		add(list, { 0.3, fh, fence }, { -fence / 2, fh / 2, 0 }, "#f59e0b", "DiamondPlate", fo)
		add(list, { 0.3, fh, fence }, { fence / 2, fh / 2, 0 }, "#f59e0b", "DiamondPlate", fo)
		local gw, gd, gh = 16, 14, 9
		add(list, { 0.6, gh, gd }, { -gw / 2, gh / 2, 0 }, "#7a4a35", "Brick", { Tag = "Garage", Collide = true })
		add(list, { 0.6, gh, gd }, { gw / 2, gh / 2, 0 }, "#7a4a35", "Brick", { Tag = "Garage", Collide = true })
		add(list, { gw, gh, 0.6 }, { 0, gh / 2, gd / 2 }, "#7a4a35", "Brick", { Tag = "Garage", Collide = true })
		add(
			list,
			{ gw + 1, 0.6, gd + 1 },
			{ 0, gh + 0.3, 0 },
			"#4a4f57",
			"Concrete",
			{ Tag = "Garage", Collide = true }
		)
		add(list, { gw - 0.6, gh - 0.4, 0.4 }, { 0, (gh - 0.4) / 2, -gd / 2 }, "#8b97a8", "CorrodedMetal", {
			Tag = "RollerDoor",
			Collide = true,
		})
		return list
	end

	-- Eingang: Rampe (1 Stud Stufe zur Lobby-Platte), Vordach mit Neonkante
	add(list, { DOOR_W, SLAB, 3 }, { 0, SLAB / 2, front - 1.7 }, "#3a3f47", "Concrete", {
		Kind = "Wedge",
		Tag = "Ramp",
		Collide = true,
		Query = true,
	})
	if s >= 2 then
		add(list, { DOOR_W + 6, 0.5, 6 }, { 0, DOOR_TOP + 0.8, front - 3 }, pal.Glass, "Glass", {
			Tag = "Canopy",
			Transparency = 0.3,
			Collide = false,
		})
		add(list, { DOOR_W + 6.2, 0.2, 0.25 }, { 0, DOOR_TOP + 0.6, front - 6 }, neonHex, "Neon", {
			Tag = "Canopy",
			Shadow = false,
		})
	end
	-- Tresor in der Lobby (hinten rechts) – glüht rot, wenn voll (Client)
	local vx, vz = inner * 0.72, inner * 0.72
	add(list, { 5, 6, 3 }, { vx, SLAB + 3, vz + 0.5 }, "#1f2937", "DiamondPlate", { Tag = "Vault", Collide = true })
	add(list, { 0.6, 4, 4 }, { vx, SLAB + 3.2, vz - 1.3 }, "#c0c7d4", "Metal", {
		Shape = "Cylinder",
		Rot = { 0, 90, 0 },
		Tag = "Vault",
		Attr = { Vault = true },
	})
	add(list, { 0.3, 4.6, 4.6 }, { vx, SLAB + 3.2, vz - 1.15 }, gold, "Neon", {
		Shape = "Cylinder",
		Rot = { 0, 90, 0 },
		Tag = "VaultRing",
		Shadow = false,
		Attr = { VaultRing = true },
	})
	-- Etagen-Panel neben der Aufzugstür + Empfangstresen
	add(list, { 1.4, 2.2, 0.3 }, { CORE / 2 + 1.4, SLAB + 4, -CORE / 2 - 0.2 }, "#0b0f17", "SmoothPlastic", {
		Tag = "ElevatorPanel",
		Attr = { ElevatorPanel = true },
	})
	add(list, { 7, 3.4, 2 }, { inner * 0.6, SLAB + 1.7, -inner * 0.28 }, pal.Accent, "Marble", {
		Tag = "Reception",
		Collide = true,
	})
	add(list, { 7.4, 0.25, 2.4 }, { inner * 0.6, SLAB + 3.5, -inner * 0.28 }, neonHex, "Neon", {
		Tag = "Reception",
		Shadow = false,
	})
	-- Pflanzkübel mit Bäumen links/rechts vom Eingang
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (DOOR_W / 2 + 4)
		add(list, { 3, 1.4, 3 }, { x, 0.7, front - 4 }, "#2a3342", "Marble", { Tag = "Planter", Collide = true })
		tree(list, x, front - 4, 1.4, "#3f8f3a", 1)
	end
	-- Garagentor (links, Einfahrt von der Ringstraße)
	add(list, { 0.6, 9, 14 }, { -half - 0.5, 4.5, half * 0.3 }, "#8b97a8", "CorrodedMetal", {
		Tag = "GarageDoor",
		Collide = true,
	})
	add(list, { 0.8, 1, 15 }, { -half - 0.6, 9.5, half * 0.3 }, pal.Trim, "Metal", { Tag = "GarageDoor" })
	-- Ladeplätze der Lobby-Roboter (Hausmeister, Sicherheit)
	add(list, { 0.3, 3, 3 }, { inner * 0.35, SLAB + 0.15, inner * 0.72 }, neonHex, "Neon", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "BotPad",
		Transparency = 0.3,
		Shadow = false,
	})
	add(list, { 0.3, 3, 3 }, { inner * 0.38, SLAB + 0.15, -inner * 0.55 }, "#ef4444", "Neon", {
		Shape = "Cylinder",
		Rot = VERTICAL,
		Tag = "BotPad",
		Transparency = 0.3,
		Shadow = false,
	})
	return list
end

-- ---------------------------------------------------------------------
-- 10) PERSONAL-ROBOTER (Kugelkopf mit Augen-Band, Kapselkörper, Schwebering – nur Parts, §A4)
-- ---------------------------------------------------------------------
local ROBOT_LOOK: { [string]: { [string]: any } } = {
	Intern = { Body = "#e6ecf5", Head = "#f4f6fa", Eye = "#4f8cff", H = 1.0, W = 1.0 },
	Analyst = { Body = "#9aa6b8", Head = "#d7dee8", Eye = "#22c55e", H = 1.1, W = 1.0, Tablet = true },
	Senior = { Body = "#7fb2ff", Head = "#d7dee8", Eye = "#22d3ee", H = 1.3, W = 1.1, Shoulder = true },
	Quant = { Body = "#1e1b4b", Head = "#3730a3", Eye = "#b36bff", H = 1.2, W = 1.6, Mainframe = true },
	Janitor = { Body = "#facc15", Head = "#f4f6fa", Eye = "#22c55e", H = 0.8, W = 1.1, Brush = true },
	Security = { Body = "#1e3a8a", Head = "#0b0f17", Eye = "#ef4444", H = 1.35, W = 1.1, Visor = true },
}

function TowerModels.Robot(key: string, x: number, z: number, yaw: number, group: string): { PartSpec }
	local list: { PartSpec } = {}
	local look = ROBOT_LOOK[key] or ROBOT_LOOK.Intern
	local g = G(x, 0, z, yaw)
	local h, w = look.H, look.W
	local base: Opts = { Group = group, Anim = "Bob", Shadow = false }
	local function o(extra: Opts?): Opts
		local t = table.clone(base)
		if extra then
			for k, v in pairs(extra) do
				t[k] = v
			end
		end
		return t
	end
	-- Schwebering
	put(list, g, { 0.25, 1.9 * w, 1.9 * w }, 0, 0.6, 0, look.Eye, "Neon", o({ Shape = "Cylinder", Rot = VERTICAL }))
	if look.Mainframe then
		put(list, g, { 2.4 * w, 3.2 * h, 1.6 }, 0, 2.5 * h, 0, look.Body, "Metal", o())
		put(list, g, { 1.8 * w, 2.2 * h, 0.1 }, 0, 2.6 * h, -0.82, look.Eye, "Neon", o({ Transparency = 0.2 }))
		put(list, g, { 1.4, 1.4, 1.4 }, 0, 4.6 * h, 0, look.Head, "SmoothPlastic", o({ Shape = "Ball", Anim = "Head" }))
		put(list, g, { 1.2, 0.18, 0.2 }, 0, 4.7 * h, -0.62, look.Eye, "Neon", o({ Anim = "Head" }))
		return list
	end
	-- Kapselkörper (Zylinder + Kugelabschluss)
	put(
		list,
		g,
		{ 1.8 * h, 1.3 * w, 1.3 * w },
		0,
		1.7 + 0.9 * h,
		0,
		look.Body,
		"SmoothPlastic",
		o({
			Shape = "Cylinder",
			Rot = VERTICAL,
		})
	)
	put(list, g, { 1.3 * w, 1.3 * w, 1.3 * w }, 0, 1.7, 0, look.Body, "SmoothPlastic", o({ Shape = "Ball" }))
	-- Kugelkopf mit Augen-Band
	local headY = 1.7 + 1.8 * h + 0.75
	put(list, g, { 1.3, 1.3, 1.3 }, 0, headY, 0, look.Head, "SmoothPlastic", o({ Shape = "Ball", Anim = "Head" }))
	put(list, g, { 0.95, 0.22, 0.3 }, 0, headY + 0.05, -0.52, look.Eye, "Neon", o({ Anim = "Head" }))
	if look.Tablet then
		put(
			list,
			g,
			{ 0.9, 0.06, 0.6 },
			0.45,
			1.7 + h,
			-0.75,
			look.Eye,
			"Neon",
			o({ Rot = { 30, 0, 0 }, Transparency = 0.2 })
		)
	elseif look.Shoulder then
		put(list, g, { 2.1 * w, 0.35, 0.9 }, 0, 1.7 + 1.6 * h, 0, "#d7dee8", "Metal", o())
	elseif look.Brush then
		put(list, g, { 0.4, 1.6, 1.6 }, 0, 0.3, -0.7, "#7d889a", "Fabric", o({ Shape = "Cylinder", Rot = VERTICAL }))
	elseif look.Visor then
		put(list, g, { 1.0, 0.35, 0.35 }, 0, headY + 0.05, -0.5, look.Eye, "Neon", o({ Anim = "Head" }))
	end
	return list
end

-- ---------------------------------------------------------------------
-- 11) INTERIORS (11 Abteilungen × 5 Raum-Stufen, Personal, Deko; ≤ 150 Parts je Etage)
-- ---------------------------------------------------------------------
-- Raum-Stufe -> Materialien (L1 schlicht … L5 Marmor/Gold)
local function levelLook(level: number): Pal
	local l = math.clamp(level, 1, 5)
	return ({
		{ Floor = "#3a4150", FloorMat = "SmoothPlastic", Top = "#d7dee8", TopMat = "SmoothPlastic", Trim = "#7d889a" },
		{ Floor = "#4a3a2c", FloorMat = "WoodPlanks", Top = "#b08a5a", TopMat = "Wood", Trim = "#7d889a" },
		{ Floor = "#2a3342", FloorMat = "Carpet", Top = "#cfe3f7", TopMat = "Glass", Trim = "#c0c7d4" },
		{ Floor = "#d9dde4", FloorMat = "Marble", Top = "#1f2937", TopMat = "Granite", Trim = "#c0c7d4" },
		{ Floor = "#1a1410", FloorMat = "Marble", Top = "#f4f6fa", TopMat = "Marble", Trim = "#facc15" },
	})[l]
end

local ROOM_ACCENT: { [string]: string } = {
	Office = "#4f8cff",
	Desk = "#22c55e",
	Cafe = "#f59e0b",
	Garage = "#facc15",
	Marketing = "#ec4899",
	Vault = "#facc15",
	Lab = "#22d3ee",
	Server = "#4f8cff",
	Lounge = "#b36bff",
	BotLab = "#22d3ee",
	Penthouse = "#7c5cff",
}

type Ctx = { List: { PartSpec }, H: number, Lv: Pal, Level: number, Accent: string, Lights: number, Floor: number }

-- --- Möbel-Bausteine (Gruppen-lokal; Vorderseite = lokal −Z; Drehung über G/sub) ---
-- Blickrichtung: yaw 0 = nach −Z (zur Plaza), 90 = nach −X, 180 = nach +Z, 270 = nach +X.
-- Untergruppe mit lokalem Versatz (ox, oz) und zusätzlicher Drehung
local function sub(g: Group, ox: number, oz: number, yawAdd: number?): Group
	return G(g.X + g.C * ox + g.S * oz, g.Y, g.Z - g.S * ox + g.C * oz, (g.Yaw + (yawAdd or 0)) % 360)
end

local function chair(c: Ctx, g: Group, color: string)
	put(c.List, g, { 1.8, 0.4, 1.8 }, 0, 1.6, 0, color, "Fabric", { Collide = true })
	put(c.List, g, { 1.8, 2, 0.35 }, 0, 2.7, 0.8, color, "Fabric")
	put(c.List, g, { 1.4, 0.2, 1.4 }, 0, 0.1, 0, "#1f2937", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
end

-- Schreibtisch: Nutzer sitzt bei −Z, Monitor steht bei +Z und zeigt mit der Bildseite (Front = −Z) zum Nutzer
local function desk(c: Ctx, g: Group, monitor: string?, withChair: boolean?)
	local lv = c.Lv
	put(c.List, g, { 6, 0.3, 3 }, 0, 2.6, 0, lv.Top, lv.TopMat, {
		Collide = true,
		Transparency = if lv.TopMat == "Glass" then 0.3 else 0,
	})
	put(c.List, g, { 0.3, 2.45, 2.6 }, -2.7, 1.25, 0, lv.Trim, "Metal")
	put(c.List, g, { 0.3, 2.45, 2.6 }, 2.7, 1.25, 0, lv.Trim, "Metal")
	put(c.List, g, { 2.8, 1.7, 0.15 }, 0, 3.8, 0.9, "#0b0f17", "SmoothPlastic", {
		Tag = "Monitor",
		Attr = { Monitor = monitor or "Chart", Face = "Front" },
	})
	put(c.List, g, { 1.8, 0.08, 0.6 }, 0, 2.8, -0.4, "#1f2937", "SmoothPlastic")
	if withChair then
		chair(c, sub(g, 0, -2.4, 180), "#2a3342")
	end
end

local function plant(c: Ctx, g: Group, scale: number)
	put(
		c.List,
		g,
		{ 1.6 * scale, 1.4 * scale, 1.6 * scale },
		0,
		0.7 * scale,
		0,
		"#e6ecf5",
		"Ceramic",
		{ Collide = true }
	)
	put(c.List, g, { 2.6 * scale, 2.6 * scale, 2.6 * scale }, 0, 2.6 * scale, 0, "#2f9e5b", "Grass", { Shape = "Ball" })
end

-- Sofa: Lehne bei +Z, Sitzende schauen nach −Z
local function sofa(c: Ctx, g: Group, color: string)
	put(c.List, g, { 7, 1.4, 3 }, 0, 0.9, 0, color, "Fabric", { Collide = true })
	put(c.List, g, { 7, 2.2, 0.8 }, 0, 1.9, 1.1, color, "Fabric", { Collide = true })
	put(c.List, g, { 0.8, 1.9, 3 }, -3.1, 1.3, 0, color, "Fabric")
	put(c.List, g, { 0.8, 1.9, 3 }, 3.1, 1.3, 0, color, "Fabric")
end

local function lowTable(c: Ctx, g: Group)
	put(c.List, g, { 4, 0.3, 2.4 }, 0, 1.4, 0, c.Lv.Top, c.Lv.TopMat, {
		Collide = true,
		Transparency = if c.Lv.TopMat == "Glass" then 0.3 else 0,
	})
	put(c.List, g, { 3.4, 1.25, 1.8 }, 0, 0.62, 0, c.Lv.Trim, "Metal", { Transparency = 0.5 })
end

-- Sofa mit Couchtisch davor (lokal −Z)
local function sofaSet(c: Ctx, g: Group, color: string)
	sofa(c, g, color)
	lowTable(c, sub(g, 0, -3.4))
end

-- Wand-Bildschirm: Rahmen hinten, Bildfläche (Front = −Z) – Live-Chart über das Monitor-Attribut (WP5)
local function screen(c: Ctx, g: Group, kind: string, w: number?)
	local width = w or 8
	put(c.List, g, { width + 0.6, width * 0.56 + 0.6, 0.3 }, 0, 4.6, 0.1, "#1f2937", "Metal")
	put(c.List, g, { width, width * 0.56, 0.12 }, 0, 4.6, -0.12, "#0b0f17", "SmoothPlastic", {
		Tag = "Monitor",
		Attr = { Monitor = kind, Face = "Front" },
	})
end

local function ceilingLights(c: Ctx, color: string)
	local h = c.H
	local light: LightSpec = { Range = math.clamp(h * 1.1, 14, 28), Brightness = 1.1, Color = color }
	local origin = G(0, 0, 0)
	put(c.List, origin, { h * 1.2, 0.15, 0.8 }, 0, 8.4, -h * 0.45, "#f4f6fa", "Neon", {
		Shadow = false,
		Light = light,
		Tag = "Light",
	})
	put(c.List, origin, { h * 1.2, 0.15, 0.8 }, 0, 8.4, h * 0.45, "#f4f6fa", "Neon", { Shadow = false })
end

local function floorFinish(c: Ctx)
	local w = c.H * 2 - 0.5
	put(c.List, G(0, 0, 0), { w, 0.1, w }, 0, 0.05, 0, c.Lv.Floor, c.Lv.FloorMat, { Tag = "FloorFinish" })
end

local function partition(c: Ctx, g: Group, length: number)
	put(c.List, g, { length, 4.5, 0.25 }, 0, 2.25, 0, "#cfe3f7", "Glass", { Transparency = 0.6, Collide = true })
	put(c.List, g, { length, 0.15, 0.3 }, 0, 4.5, 0, c.Accent, "Neon", { Shadow = false })
end

local function rack(c: Ctx, g: Group, led: string)
	put(c.List, g, { 2.4, 7, 3 }, 0, 3.5, 0, "#121824", "Metal", { Collide = true })
	put(c.List, g, { 0.12, 6, 0.2 }, -0.7, 3.5, -1.52, led, "Neon", { Shadow = false })
	put(
		c.List,
		g,
		{ 0.12, 6, 0.2 },
		0.7,
		3.5,
		-1.52,
		if c.Level >= 3 then "#22c55e" else led,
		"Neon",
		{ Shadow = false }
	)
end

local function rackRow(c: Ctx, g: Group, count: number, led: string)
	for i = 0, count - 1 do
		rack(c, sub(g, i * 2.6, 0), led)
	end
end

-- Theke: Vorderseite (Neon-Leiste) bei −Z
local function counter(c: Ctx, g: Group, length: number, color: string)
	put(c.List, g, { length, 3.4, 2 }, 0, 1.7, 0, color, "SmoothPlastic", { Collide = true })
	put(c.List, g, { length + 0.4, 0.25, 2.4 }, 0, 3.5, 0, c.Lv.Top, c.Lv.TopMat)
	put(c.List, g, { length, 0.15, 0.1 }, 0, 0.4, -1.02, c.Accent, "Neon", { Shadow = false })
end

local function stool(c: Ctx, g: Group)
	put(c.List, g, { 0.3, 1.2, 1.2 }, 0, 2.5, 0, c.Accent, "Fabric", { Shape = "Cylinder", Rot = VERTICAL })
	put(c.List, g, { 2.4, 0.3, 0.3 }, 0, 1.2, 0, "#c0c7d4", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
end

local function roundTable(c: Ctx, g: Group, chairColor: string?)
	put(
		c.List,
		g,
		{ 0.25, 3, 3 },
		0,
		2.6,
		0,
		c.Lv.Top,
		c.Lv.TopMat,
		{ Shape = "Cylinder", Rot = VERTICAL, Collide = true }
	)
	put(c.List, g, { 2.5, 0.4, 0.4 }, 0, 1.25, 0, "#1f2937", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
	if chairColor then
		chair(c, sub(g, 0, 2.3), chairColor)
		chair(c, sub(g, 0, -2.3, 180), chairColor)
	end
end

local function fruitBowl(c: Ctx, g: Group)
	for i, color in ipairs({ "#f59e0b", "#ef4444", "#22c55e" }) do
		put(c.List, g, { 0.6, 0.6, 0.6 }, (i - 2) * 0.6, 3.95, 0, color, "SmoothPlastic", { Shape = "Ball" })
	end
end

local function waterCooler(c: Ctx, g: Group)
	put(c.List, g, { 1.4, 3, 1.4 }, 0, 1.5, 0, "#e6ecf5", "SmoothPlastic", { Collide = true })
	put(
		c.List,
		g,
		{ 1.6, 1.1, 1.1 },
		0,
		3.8,
		0,
		"#93c5fd",
		"Glass",
		{ Shape = "Cylinder", Rot = VERTICAL, Transparency = 0.3 }
	)
end

local function meetingTable(c: Ctx, g: Group)
	put(c.List, g, { 6, 0.3, 3 }, 0, 2.6, 0, c.Lv.Top, c.Lv.TopMat, { Collide = true })
	put(c.List, g, { 4, 2.45, 1 }, 0, 1.25, 0, c.Lv.Trim, "Metal")
	chair(c, sub(g, 0, -2.2, 180), "#1f2937")
	chair(c, sub(g, 0, 2.2), "#1f2937")
end

-- Trading-Desk: zwei abgewinkelte Platten, drei Monitore (Mitte = eigene Live-Position, WP5 "Desk")
local function tradingDesk(c: Ctx, g: Group, withChair: boolean?)
	local lv = c.Lv
	put(c.List, g, { 5, 0.3, 2.6 }, -2.3, 2.6, 0, lv.Top, lv.TopMat, { Rot = { 0, -12, 0 }, Collide = true })
	put(c.List, g, { 5, 0.3, 2.6 }, 2.3, 2.6, 0, lv.Top, lv.TopMat, { Rot = { 0, 12, 0 }, Collide = true })
	put(c.List, g, { 8.4, 2.4, 0.4 }, 0, 1.3, 0.9, lv.Trim, "Metal")
	for i, x in ipairs({ -2.6, 0, 2.6 }) do
		put(c.List, g, { 2.4, 1.5, 0.12 }, x, 3.8 + (if i == 2 then 0.25 else 0), 0.95, "#0b0f17", "SmoothPlastic", {
			Tag = "Monitor",
			Rot = { 0, if i == 1 then -12 elseif i == 3 then 12 else 0, 0 },
			Attr = { Monitor = if i == 2 then "Desk" else "Chart", Face = "Front" },
		})
	end
	if withChair then
		chair(c, sub(g, 0, -2.2, 180), "#121824")
	end
end

local function carModel(c: Ctx, g: Group, color: string)
	put(c.List, g, { 4.2, 1.4, 9 }, 0, 1.4, 0, color, "SmoothPlastic", { Collide = true })
	put(c.List, g, { 3.6, 1.2, 4.4 }, 0, 2.6, 0.4, "#121824", "Glass", { Transparency = 0.2 })
	for _, p in ipairs({ { -2.1, -3 }, { 2.1, -3 }, { -2.1, 3 }, { 2.1, 3 } }) do
		put(c.List, g, { 0.7, 1.6, 1.6 }, p[1], 0.8, p[2], "#0b0f17", "SmoothPlastic", { Shape = "Cylinder" })
	end
end

-- --- Raum-Rezepte: { fn, fx, fz, yaw, minLevel, lobbyOk } (fx/fz = Anteil der Innen-Halbbreite) ---
-- Freie Zonen: rechts hinten, rechts Mitte, links Mitte, Rückwand Mitte. Deko-Plätze liegen vorn links/rechts und
-- hinten links (Penthouse: alle Ecken + Seitenmitten), die Aufzugs-Ankunft vor dem Kern bleibt frei.
type Place = { any } -- { fn: (Ctx, Group) -> (), fx, fz, yaw, minLevel, lobbyOk }

local function office(): { Place }
	return {
		{
			function(c, g)
				desk(c, g, "Chart", true)
			end,
			0.55,
			0.5,
			90,
			1,
			false,
		},
		{
			function(c, g)
				desk(c, g, "Chart", true)
			end,
			0.55,
			0.12,
			90,
			1,
			false,
		},
		{
			function(c, g)
				plant(c, g, 1)
			end,
			0.86,
			-0.3,
			0,
			1,
			true,
		},
		{
			function(c, g)
				desk(c, g, "Chart", true)
			end,
			-0.6,
			-0.05,
			270,
			2,
			true,
		},
		{
			function(c, g)
				waterCooler(c, g)
			end,
			0.88,
			0.88,
			0,
			2,
			false,
		},
		{
			function(c, g)
				desk(c, g, "Chart", true)
			end,
			0.15,
			0.72,
			0,
			3,
			true,
		},
		{
			function(c, g)
				partition(c, g, 9)
			end,
			0.55,
			0.31,
			0,
			3,
			false,
		},
		{
			function(c, g)
				meetingTable(c, g)
			end,
			0.6,
			-0.3,
			90,
			4,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Candles", 7)
			end,
			-0.3,
			0.93,
			0,
			5,
			true,
		},
		{
			function(c, g)
				plant(c, g, 1.2)
			end,
			-0.86,
			0.32,
			0,
			5,
			true,
		},
	}
end

local function deskRoom(): { Place }
	return {
		{
			function(c, g)
				tradingDesk(c, g, true)
			end,
			0.55,
			0.5,
			90,
			1,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Candles", 12)
			end,
			0.0,
			0.93,
			0,
			1,
			true,
		},
		{
			function(c, g)
				tradingDesk(c, g, true)
			end,
			0.55,
			0.05,
			90,
			2,
			false,
		},
		{
			function(c, g)
				plant(c, g, 1)
			end,
			-0.86,
			0.35,
			0,
			2,
			true,
		},
		{
			function(c, g)
				tradingDesk(c, g, true)
			end,
			-0.6,
			-0.05,
			270,
			3,
			true,
		},
		{
			function(c, g)
				put(c.List, g, { 14, 0.8, 0.2 }, 0, 8.2, 0, "#0b0f17", "SmoothPlastic", {
					Tag = "Monitor",
					Attr = { Monitor = "Ticker", Face = "Front" },
				})
			end,
			0.0,
			0.95,
			0,
			4,
			true,
		},
		{
			function(c, g)
				screen(c, g, "Heatmap", 7)
			end,
			0.92,
			-0.25,
			90,
			5,
			false,
		},
	}
end

local function cafe(): { Place }
	return {
		{
			function(c, g)
				counter(c, g, 10, "#e6ecf5")
				fruitBowl(c, g)
			end,
			0.5,
			0.78,
			0,
			1,
			false,
		},
		{
			function(c, g)
				stool(c, g)
				stool(c, sub(g, 2.6, 0))
			end,
			0.36,
			0.55,
			0,
			1,
			false,
		},
		{
			function(c, g)
				roundTable(c, g, "#f59e0b")
			end,
			-0.55,
			0.25,
			0,
			1,
			true,
		},
		{
			function(c, g)
				roundTable(c, g, "#22c55e")
			end,
			0.55,
			0.0,
			0,
			2,
			false,
		},
		{
			function(c, g)
				plant(c, g, 1.1)
			end,
			-0.86,
			0.42,
			0,
			2,
			true,
		},
		{
			function(c, g)
				-- Menü-Tafel (farbige Felder statt Text)
				put(c.List, g, { 6, 3.5, 0.3 }, 0, 5.8, 0, "#121824", "SmoothPlastic")
				for i, color in ipairs({ "#f59e0b", "#22c55e", "#ec4899" }) do
					put(c.List, g, { 1.5, 2.6, 0.1 }, (i - 2) * 1.9, 5.8, -0.2, color, "Neon", {
						Shadow = false,
						Transparency = 0.3,
					})
				end
			end,
			0.5,
			0.96,
			0,
			3,
			false,
		},
		{
			function(c, g)
				sofaSet(c, g, "#f59e0b")
			end,
			-0.66,
			-0.25,
			270,
			4,
			true,
		},
		{
			function(c, g)
				-- Smoothie-Mixer auf der Theke
				for i = 1, 3 do
					put(
						c.List,
						g,
						{ 1.4, 0.8, 0.8 },
						(i - 2) * 1.4,
						4.3,
						0,
						({ "#22c55e", "#ec4899", "#f59e0b" })[i],
						"Glass",
						{
							Shape = "Cylinder",
							Rot = VERTICAL,
							Transparency = 0.25,
						}
					)
				end
			end,
			0.3,
			0.78,
			0,
			5,
			false,
		},
	}
end

local function garage(): { Place }
	return {
		{
			function(c, g)
				-- Auto-Aufzug: Plattform fährt langsam auf/ab (Client), Säulen, Auto
				put(c.List, g, { 7, 0.4, 11 }, 0, 0.3, 0, "#3a3f47", "DiamondPlate", { Group = "Lift", Anim = "Lift" })
				put(c.List, g, { 0.8, 8, 0.8 }, -3.9, 4, -5.6, "#facc15", "Metal")
				put(c.List, g, { 0.8, 8, 0.8 }, 3.9, 4, 5.6, "#facc15", "Metal")
				carModel(c, G(g.X, 0.5, g.Z, g.Yaw), c.Accent)
			end,
			0.55,
			0.5,
			0,
			1,
			false,
		},
		{
			function(c, g)
				for i = 1, 3 do
					put(c.List, g, { 1, 2.6, 2.6 }, 0, 0.5 + (i - 1) * 1.05, 0, "#0b0f17", "SmoothPlastic", {
						Shape = "Cylinder",
						Rot = VERTICAL,
					})
				end
			end,
			-0.86,
			-0.38,
			0,
			1,
			true,
		},
		{
			function(c, g)
				-- Werkzeugwand
				put(c.List, g, { 8, 5, 0.3 }, 0, 3.5, 0, "#7d889a", "DiamondPlate")
				for i = 1, 3 do
					put(
						c.List,
						g,
						{ 0.4, 1.8, 0.3 },
						(i - 2) * 2,
						3.6,
						-0.3,
						"#ef4444",
						"Metal",
						{ Rot = { 0, 0, (i - 2) * 25 } }
					)
				end
			end,
			-0.35,
			0.95,
			0,
			2,
			true,
		},
		{
			function(c, g)
				for i = -1, 1 do
					put(
						c.List,
						g,
						{ 0.3, 0.06, 8 },
						i * 4,
						0.13,
						0,
						"#facc15",
						"Neon",
						{ Shadow = false, Transparency = 0.2 }
					)
				end
			end,
			0.55,
			-0.05,
			90,
			2,
			false,
		},
		{
			function(c, g)
				carModel(c, g, "#d7dee8")
			end,
			-0.58,
			0.1,
			0,
			3,
			true,
		},
		{
			function(c, g)
				-- Lackier-Box (Glas) + Neon-Leiste
				put(c.List, g, { 8, 6, 0.3 }, 0, 3, 0, "#cfe3f7", "Glass", { Transparency = 0.6 })
				put(c.List, g, { 8, 0.2, 0.4 }, 0, 6, 0, "#22d3ee", "Neon", { Shadow = false })
			end,
			0.55,
			-0.32,
			0,
			4,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 6)
			end,
			0.93,
			0.12,
			90,
			5,
			false,
		},
	}
end

local function marketing(): { Place }
	return {
		{
			function(c, g)
				-- Studio-Hintergrund (Hohlkehle steigt zur Wand an)
				put(c.List, g, { 10, 7, 0.3 }, 0, 3.5, 0.6, "#f4f6fa", "SmoothPlastic")
				put(c.List, g, { 10, 0.6, 3 }, 0, 0.3, -1, "#f4f6fa", "SmoothPlastic", { Kind = "Wedge" })
			end,
			0.55,
			0.8,
			0,
			1,
			false,
		},
		{
			function(c, g)
				-- Kamera auf Stativ (Objektiv zeigt zur Hohlkehle)
				put(c.List, g, { 3.6, 0.3, 0.3 }, 0, 1.8, 0, "#1f2937", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
				put(c.List, g, { 1.2, 1, 1.8 }, 0, 4, 0, "#0b0f17", "SmoothPlastic")
				put(
					c.List,
					g,
					{ 0.2, 0.7, 0.7 },
					0,
					4,
					-1,
					"#4f8cff",
					"Glass",
					{ Shape = "Cylinder", Rot = { 0, 90, 0 } }
				)
			end,
			0.5,
			0.2,
			180,
			1,
			false,
		},
		{
			function(c, g)
				put(c.List, g, { 6, 0.3, 0.3 }, 0, 3, 0, "#1f2937", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
				put(c.List, g, { 1.6, 1.4, 1.4 }, 0, 6.2, 0, "#121824", "Metal", {
					Rot = { -25, 0, 0 },
					Light = { Kind = "Spot", Range = 18, Brightness = 2, Color = "#ffe7c2", Face = "Front", Angle = 45 },
				})
			end,
			0.25,
			0.42,
			200,
			2,
			false,
		},
		{
			function(c, g)
				-- Mood-Board (farbige Felder)
				put(c.List, g, { 8, 4.5, 0.25 }, 0, 4.2, 0, "#1a2130", "SmoothPlastic")
				for i, color in ipairs({ "#ec4899", "#4f8cff", "#f59e0b", "#22c55e" }) do
					put(c.List, g, { 1.6, 2.4, 0.1 }, (i - 2.5) * 1.9, 4.2, -0.18, color, "SmoothPlastic")
				end
			end,
			-0.55,
			0.95,
			0,
			2,
			true,
		},
		{
			function(c, g)
				sofa(c, g, "#ec4899")
			end,
			-0.64,
			-0.15,
			270,
			3,
			true,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 8)
			end,
			0.93,
			-0.15,
			90,
			4,
			false,
		},
		{
			function(c, g)
				plant(c, g, 1.2)
			end,
			-0.86,
			0.42,
			0,
			5,
			true,
		},
	}
end

local function vaultRoom(): { Place }
	return {
		{
			function(c, g)
				-- runde Tresortür (Achse zeigt in den Raum) mit Riegelkreuz
				put(c.List, g, { 0.8, 7.5, 7.5 }, 0, 4.2, 0, "#c0c7d4", "Metal", {
					Shape = "Cylinder",
					Rot = { 0, 90, 0 },
					Collide = true,
				})
				put(
					c.List,
					g,
					{ 0.4, 8.2, 8.2 },
					0,
					4.2,
					0.3,
					"#facc15",
					"Metal",
					{ Shape = "Cylinder", Rot = { 0, 90, 0 } }
				)
				put(c.List, g, { 2.4, 0.4, 0.4 }, 0, 4.2, -0.6, "#1f2937", "Metal", { Rot = { 0, 0, 45 } })
				put(c.List, g, { 2.4, 0.4, 0.4 }, 0, 4.2, -0.6, "#1f2937", "Metal", { Rot = { 0, 0, -45 } })
			end,
			0.45,
			0.93,
			0,
			1,
			false,
		},
		{
			function(c, g)
				for i = 1, 3 do
					put(c.List, g, { 2, 0.8, 1 }, (i - 2) * 2.2, 0.5, 0, "#facc15", "Metal", { Collide = true })
				end
				if c.Level >= 3 then
					put(c.List, g, { 2, 0.8, 1 }, -1.1, 1.3, 0, "#facc15", "Metal")
					put(c.List, g, { 2, 0.8, 1 }, 1.1, 1.3, 0, "#facc15", "Metal")
				end
			end,
			0.6,
			0.25,
			0,
			1,
			false,
		},
		{
			function(c, g)
				-- Schließfach-Wand
				put(c.List, g, { 10, 7, 1 }, 0, 3.5, 0, "#7d889a", "DiamondPlate", { Collide = true })
				put(c.List, g, { 10, 0.2, 0.2 }, 0, 6.8, -0.55, "#facc15", "Neon", { Shadow = false })
			end,
			-0.55,
			0.95,
			0,
			2,
			true,
		},
		{
			function(c, g)
				-- Laser-Gitter
				for i = 1, 3 do
					put(c.List, g, { 9, 0.08, 0.08 }, 0, 0.8 + i * 1.1, 0, "#ef4444", "Neon", { Shadow = false })
				end
			end,
			0.55,
			-0.2,
			0,
			3,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 6)
			end,
			-0.93,
			-0.05,
			270,
			4,
			true,
		},
		{
			function(c, g)
				put(c.List, g, { 2.4, 3.6, 2.4 }, 0, 1.8, 0, "#1a1410", "Marble", { Collide = true })
				put(c.List, g, { 1.2, 1.2, 1.2 }, 0, 4.2, 0, "#a5f3fc", "Glass", {
					Shape = "Ball",
					Anim = "Spin",
					Group = "Gem",
					Transparency = 0.1,
				})
			end,
			-0.52,
			-0.38,
			0,
			5,
			true,
		},
	}
end

local function lab(): { Place }
	local function bench(c: Ctx, g: Group)
		put(c.List, g, { 7, 0.3, 3 }, 0, 3, 0, "#f4f6fa", "SmoothPlastic", { Collide = true })
		put(c.List, g, { 6.6, 2.8, 2.6 }, 0, 1.45, 0, "#7d889a", "Metal")
		put(
			c.List,
			g,
			{ 1.4, 0.7, 0.7 },
			-2,
			3.85,
			0,
			"#22d3ee",
			"Glass",
			{ Shape = "Cylinder", Rot = VERTICAL, Transparency = 0.3 }
		)
		put(c.List, g, { 1.0, 0.6, 0.6 }, -0.8, 3.65, 0.3, "#22c55e", "Glass", {
			Shape = "Cylinder",
			Rot = VERTICAL,
			Transparency = 0.3,
		})
	end
	return {
		{
			function(c, g)
				bench(c, g)
			end,
			0.55,
			0.55,
			0,
			1,
			false,
		},
		{
			function(c, g)
				put(c.List, g, { 1.4, 1.2, 1.4 }, 0, 0.6, 0, "#1f2937", "Metal", { Collide = true })
				put(c.List, g, { 3.2, 3.2, 3.2 }, 0, 3, 0, "#22d3ee", "Neon", {
					Shape = "Ball",
					Transparency = 0.55,
					Anim = "Spin",
					Group = "Globe",
					Shadow = false,
				})
			end,
			0.55,
			0.05,
			0,
			1,
			false,
		},
		{
			function(c, g)
				bench(c, g)
			end,
			-0.6,
			-0.05,
			270,
			2,
			true,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 7)
			end,
			0.0,
			0.93,
			0,
			2,
			true,
		},
		{
			function(c, g)
				partition(c, g, 9)
			end,
			0.55,
			0.3,
			0,
			3,
			false,
		},
		{
			function(c, g)
				-- Kühlschrank-Säulen mit Proben
				for i = 1, 2 do
					put(
						c.List,
						g,
						{ 2, 6, 2 },
						(i - 1.5) * 2.3,
						3,
						0,
						"#e6ecf5",
						"Glass",
						{ Transparency = 0.25, Collide = true }
					)
				end
			end,
			0.86,
			-0.32,
			90,
			4,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Heatmap", 6)
			end,
			-0.93,
			0.32,
			270,
			5,
			true,
		},
	}
end

local function serverRoom(): { Place }
	return {
		{
			function(c, g)
				rackRow(c, g, 3, "#4f8cff")
			end,
			0.35,
			0.6,
			0,
			1,
			false,
		},
		{
			function(c, g)
				rackRow(c, g, 3, "#4f8cff")
			end,
			0.35,
			0.15,
			0,
			2,
			false,
		},
		{
			function(c, g)
				-- Kabeltrasse unter der Decke
				put(c.List, g, { 16, 0.4, 1.2 }, 0, 7.9, 0, "#7d889a", "DiamondPlate")
			end,
			0.45,
			0.38,
			0,
			2,
			false,
		},
		{
			function(c, g)
				rackRow(c, g, 2, "#22d3ee")
			end,
			-0.72,
			-0.12,
			270,
			3,
			true,
		},
		{
			function(c, g)
				-- Kühlung mit blauem Licht
				put(c.List, g, { 4, 3, 2 }, 0, 1.5, 0, "#d7dee8", "Metal", { Collide = true })
				put(c.List, g, { 3, 0.2, 0.2 }, 0, 3.1, -1, "#22d3ee", "Neon", {
					Shadow = false,
					Light = { Range = 12, Brightness = 1.2, Color = "#22d3ee" },
				})
			end,
			-0.4,
			0.9,
			0,
			4,
			true,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 6)
			end,
			0.93,
			-0.35,
			90,
			5,
			false,
		},
	}
end

local function lounge(): { Place }
	return {
		{
			function(c, g)
				sofaSet(c, g, "#7c5cff")
			end,
			0.55,
			0.62,
			0,
			1,
			false,
		},
		{
			function(c, g)
				-- Kamin (Neon-Glut hinter Glas)
				put(c.List, g, { 7, 4, 1.6 }, 0, 2, 0, "#1a1410", "Marble", { Collide = true })
				put(c.List, g, { 5, 1.4, 0.3 }, 0, 1.6, -0.7, "#f97316", "Neon", {
					Shadow = false,
					Light = { Range = 12, Brightness = 1.4, Color = "#ffb070" },
				})
			end,
			-0.45,
			0.95,
			0,
			1,
			true,
		},
		{
			function(c, g)
				-- Bücherregal
				put(c.List, g, { 6, 7, 1.4 }, 0, 3.5, 0, "#5b3a24", "Wood", { Collide = true })
				for i = 1, 3 do
					put(
						c.List,
						g,
						{ 5.2, 1.2, 0.3 },
						0,
						1.4 + i * 1.8,
						-0.6,
						({ "#3b5bdb", "#ef4444", "#22c55e" })[i],
						"SmoothPlastic"
					)
				end
			end,
			0.93,
			0.05,
			90,
			2,
			false,
		},
		{
			function(c, g)
				sofa(c, g, "#3b5bdb")
			end,
			-0.64,
			-0.15,
			270,
			3,
			true,
		},
		{
			function(c, g)
				put(c.List, g, { 9, 0.08, 6 }, 0, 0.12, 0, "#2a1f4a", "Fabric")
			end,
			0.45,
			0.3,
			0,
			3,
			false,
		},
		{
			function(c, g)
				plant(c, g, 1.3)
			end,
			0.86,
			-0.4,
			0,
			4,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Candles", 8)
			end,
			0.12,
			0.95,
			0,
			5,
			true,
		},
	}
end

local function botLab(): { Place }
	local function arm(c: Ctx, g: Group)
		put(c.List, g, { 2, 1, 2 }, 0, 0.5, 0, "#1f2937", "Metal", { Collide = true })
		put(c.List, g, { 0.6, 3.4, 0.6 }, 0, 2.6, 0, "#facc15", "Metal", { Group = "Arm", Anim = "Arm" })
		put(c.List, g, { 0.5, 0.5, 2.8 }, 0, 4.2, -1.1, "#facc15", "Metal", { Group = "Arm", Anim = "Arm" })
		put(
			c.List,
			g,
			{ 0.6, 0.6, 0.6 },
			0,
			4.2,
			-2.5,
			"#22d3ee",
			"Neon",
			{ Group = "Arm", Anim = "Arm", Shadow = false }
		)
	end
	local function pod(c: Ctx, g: Group)
		put(c.List, g, { 0.6, 3.4, 3.4 }, 0, 0.3, 0, "#1f2937", "Metal", { Shape = "Cylinder", Rot = VERTICAL })
		put(
			c.List,
			g,
			{ 5.5, 3, 3 },
			0,
			3.3,
			0,
			"#cfe3f7",
			"Glass",
			{ Shape = "Cylinder", Rot = VERTICAL, Transparency = 0.65 }
		)
		put(
			c.List,
			g,
			{ 0.25, 3.5, 3.5 },
			0,
			6,
			0,
			"#22d3ee",
			"Neon",
			{ Shape = "Cylinder", Rot = VERTICAL, Shadow = false }
		)
	end
	return {
		{
			function(c, g)
				arm(c, g)
			end,
			0.5,
			0.55,
			0,
			1,
			false,
		},
		{
			function(c, g)
				pod(c, g)
			end,
			0.78,
			0.05,
			0,
			1,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Chart", 8)
			end,
			0.0,
			0.93,
			0,
			1,
			true,
		},
		{
			function(c, g)
				arm(c, g)
			end,
			-0.6,
			0.0,
			270,
			2,
			true,
		},
		{
			function(c, g)
				pod(c, g)
			end,
			0.4,
			0.12,
			0,
			3,
			false,
		},
		{
			function(c, g)
				screen(c, g, "Desk", 6)
			end,
			-0.93,
			0.38,
			270,
			4,
			true,
		},
		{
			function(c, g)
				put(c.List, g, { 8, 0.3, 3 }, 0, 3, 0, "#f4f6fa", "SmoothPlastic", { Collide = true })
				put(c.List, g, { 7.6, 2.8, 2.6 }, 0, 1.45, 0, "#1f2937", "Metal")
			end,
			0.55,
			-0.3,
			0,
			5,
			false,
		},
	}
end

local function penthouse(): { Place }
	return {
		{
			function(c, _g)
				-- Balkon hinten vor der Fassade: Platte, Glasgeländer, Pool, zwei Liegen (nur Optik)
				local h: number = c.H
				local depth = 9
				local z0 = h + 2.2 -- Innenkante (vor der Vorhangfassade)
				local zc = z0 + depth / 2
				local origin = G(0, 0, 0)
				put(c.List, origin, { h * 2, 0.6, depth }, 0, -0.3, zc, "#e6ecf5", "Marble", { Collide = true })
				put(
					c.List,
					origin,
					{ h * 2, 3, 0.2 },
					0,
					1.5,
					z0 + depth - 0.1,
					"#cfe3f7",
					"Glass",
					{ Transparency = 0.6, Collide = true }
				)
				put(c.List, origin, { h * 2, 0.15, 0.25 }, 0, 3, z0 + depth - 0.1, c.Accent, "Neon", { Shadow = false })
				put(c.List, origin, { h * 0.9, 0.5, 5 }, -h * 0.45, 0.25, zc, "#e6ecf5", "Marble")
				put(c.List, origin, { h * 0.9 - 1, 0.3, 4 }, -h * 0.45, 0.55, zc, "#22d3ee", "Glass", {
					Transparency = 0.25,
					Reflectance = 0.3,
				})
				for i = 1, 2 do
					local x = h * (0.2 + i * 0.22)
					put(c.List, origin, { 2.4, 0.5, 5 }, x, 0.6, zc, "#f4f6fa", "Fabric", { Collide = true })
					put(c.List, origin, { 2.4, 1.8, 1.4 }, x, 1.5, zc + 2.2, "#f4f6fa", "Fabric", { Kind = "Wedge" })
				end
			end,
			0,
			0,
			0,
			1,
			true,
		},
		{
			function(c, g)
				-- Küchen-Insel mit Hocker
				counter(c, g, 7, "#1a1410")
				stool(c, sub(g, 0, -2.4))
			end,
			0.42,
			0.05,
			90,
			2,
			true,
		},
		{
			function(c, g)
				sofa(c, g, "#7c5cff")
			end,
			-0.3,
			0.4,
			0,
			3,
			true,
		},
		{
			function(c, g)
				screen(c, g, "Candles", 9)
			end,
			0.93,
			0.45,
			90,
			4,
			true,
		},
		{
			function(c, g)
				plant(c, g, 1.3)
			end,
			-0.4,
			-0.45,
			0,
			5,
			true,
		},
	}
end

local ROOM_RECIPES: { [string]: () -> { Place } } = {
	Office = office,
	Desk = deskRoom,
	Cafe = cafe,
	Garage = garage,
	Marketing = marketing,
	Vault = vaultRoom,
	Lab = lab,
	Server = serverRoom,
	Lounge = lounge,
	BotLab = botLab,
	Penthouse = penthouse,
}

-- Standplätze des Personals (Anteile der Innen-Halbbreite + Blickrichtung) – freie Flächen zwischen Möbeln
local STAFF_SPOTS_DEFAULT: { { number } } = { { 0.3, -0.3, 200 }, { -0.36, -0.32, 160 }, { -0.3, 0.36, 120 } }
local STAFF_SPOTS: { [string]: { { number } } } = {
	Penthouse = { { 0.3, -0.3, 200 }, { -0.36, -0.32, 160 }, { 0.2, 0.62, 180 } },
}

-- Feste Deko-Plätze (§B4.8): 3 je Etage, 8 im Penthouse; Blick zur Mitte
local SLOT_FRACTIONS: { { number } } = {
	{ -0.62, -0.62 },
	{ 0.62, -0.62 },
	{ -0.62, 0.62 },
	{ 0.62, 0.62 },
	{ 0.0, 0.78 },
	{ -0.82, 0.0 },
	{ 0.82, 0.0 },
	{ 0.0, -0.84 },
}

local function innerHalf(footprint: number): number
	return footprint / 2 - 1.4
end

function TowerModels.DecorSlots(room: string, footprint: number?, floor: number?): { Slot }
	local count = ROOM_SLOTS[room] or SLOTS_PER_FLOOR
	count = math.clamp(count, 1, #SLOT_FRACTIONS)
	local h = innerHalf(if finite(footprint) then footprint :: number else SMALL)
	local out: { Slot } = {}
	for i = 1, count do
		local f = SLOT_FRACTIONS[i]
		local x, z = f[1] * h, f[2] * h
		-- EG: Platz 4 (hinten rechts) liegt am Tresor -> etwas zur Mitte rücken
		if floor == 1 and i == 4 then
			x, z = x * 0.6, z * 0.95
		end
		local yaw = if x == 0 and z == 0 then 0 else math.deg(math.atan2(x, z))
		table.insert(out, { X = r3(x), Z = r3(z), Yaw = r3(yaw) })
	end
	return out
end

-- Deko-Lieferant (DecorModels.Specs) – registriert sich beim Laden selbst
local decorProvider: ((key: string) -> { PartSpec })? = nil

function TowerModels.SetDecorProvider(fn: (key: string) -> { PartSpec })
	if type(fn) == "function" then
		decorProvider = fn
	end
end

local function decorSpecs(key: string): { PartSpec }
	if decorProvider == nil then
		pcall(function()
			local here: any = script
			if typeof(here) == "Instance" then
				local module = here.Parent and here.Parent:FindFirstChild("DecorModels")
				if module and module:IsA("ModuleScript") then
					local loader: any = require
					loader(module) -- registriert sich über SetDecorProvider
				end
			end
		end)
	end
	local provider = decorProvider
	if provider == nil then
		return {}
	end
	local ok, result = pcall(provider, key)
	return if ok and type(result) == "table" then result else {}
end

-- Teile einer Spec-Liste an eine Stelle (x, z, yaw) verschieben/drehen
local function transformInto(list: { PartSpec }, source: { PartSpec }, g: Group, extra: Opts?)
	for _, spec in ipairs(source) do
		local o: Opts = {}
		for key, value in pairs(spec :: any) do
			if key ~= "Size" and key ~= "Pos" then
				o[key] = value
			end
		end
		if extra then
			for key, value in pairs(extra) do
				o[key] = value
			end
		end
		put(list, g, spec.Size, spec.Pos[1], spec.Pos[2], spec.Pos[3], spec.Color, spec.Material, o)
	end
end

function TowerModels.Interior(
	room: string,
	level: number,
	staff: { string },
	decor: { string },
	footprint: number?,
	floor: number?
): { PartSpec }
	local key = if ROOM_RECIPES[room] then room else "Office"
	local lv = if finite(level) then math.clamp(math.floor(level), 1, 5) else 1
	local size = if finite(footprint) then math.clamp(footprint :: number, 24, 80) else SMALL
	local floorIndex = if finite(floor) then math.floor(floor :: number) else 2
	local h = innerHalf(size)
	local c: Ctx = {
		List = {},
		H = h,
		Lv = levelLook(lv),
		Level = lv,
		Accent = ROOM_ACCENT[key] or "#4f8cff",
		Lights = 0,
		Floor = floorIndex,
	}
	-- 1) Boden, Deckenlichter, Akzentwand
	floorFinish(c)
	ceilingLights(c, if key == "Lounge" or key == "Penthouse" then "#ffe2c4" else "#e6f0ff")
	put(
		c.List,
		G(0, 0, 0),
		{ h * 2 - 2, 0.25, 0.25 },
		0,
		0.3,
		h - 0.2,
		c.Accent,
		"Neon",
		{ Shadow = false, Transparency = 0.15 }
	)
	-- Aufzugstür (vorn am Kern) – Rahmen + zwei Türflügel
	put(c.List, G(0, 0, 0), { 6.4, 8, 0.3 }, 0, 4, -CORE / 2 - 0.15, "#1f2937", "Metal", { Tag = "ElevatorFrame" })
	put(
		c.List,
		G(0, 0, 0),
		{ 2.4, 7.2, 0.2 },
		-1.2,
		3.6,
		-CORE / 2 - 0.35,
		"#c0c7d4",
		"Metal",
		{ Tag = "ElevatorDoor", Group = "DoorL" }
	)
	put(
		c.List,
		G(0, 0, 0),
		{ 2.4, 7.2, 0.2 },
		1.2,
		3.6,
		-CORE / 2 - 0.35,
		"#c0c7d4",
		"Metal",
		{ Tag = "ElevatorDoor", Group = "DoorR" }
	)
	put(
		c.List,
		G(0, 0, 0),
		{ 4.8, 0.15, 0.2 },
		0,
		7.4,
		-CORE / 2 - 0.4,
		c.Accent,
		"Neon",
		{ Shadow = false, Tag = "ElevatorLight" }
	)
	-- 2) Raum-Möbel nach Stufe (EG: Bereiche am Tresor/Empfang frei lassen)
	for _, place in ipairs(ROOM_RECIPES[key]()) do
		local fn = place[1] :: (Ctx, Group) -> ()
		local fx, fz, yaw = place[2] :: number, place[3] :: number, place[4] :: number
		local minLevel, lobbyOk = place[5] :: number, place[6] :: boolean
		if lv >= minLevel and (floorIndex ~= 1 or lobbyOk) then
			fn(c, G(fx * h, 0, fz * h, yaw))
		end
	end
	-- 3) Personal-Roboter an ihren Arbeitsplätzen
	local spots = STAFF_SPOTS[key] or STAFF_SPOTS_DEFAULT
	for i, staffKey in ipairs(staff) do
		if i > 3 then
			break
		end
		local spot = spots[i]
		if type(staffKey) == "string" and ROBOT_LOOK[staffKey] and spot then
			local robot = TowerModels.Robot(staffKey, spot[1] * h, spot[2] * h, spot[3], "Robot" .. i)
			for _, spec in ipairs(robot) do
				table.insert(c.List, spec)
			end
		end
	end
	-- 4) Deko in den festen Plätzen
	local slots = TowerModels.DecorSlots(key, size, floorIndex)
	for i, decorKey in ipairs(decor) do
		local slot = slots[i]
		if slot and type(decorKey) == "string" and decorKey ~= "" then
			local specs = decorSpecs(decorKey)
			if #specs > 0 then
				transformInto(c.List, specs, G(slot.X, 0, slot.Z, slot.Yaw), { Group = "Decor" .. i })
			end
		end
	end
	-- 5) Budget (≤ 150 Parts): Überschuss am Ende abschneiden (Deko zuletzt, Raum bleibt vollständig)
	while #c.List > MAX_INTERIOR do
		table.remove(c.List)
	end
	return c.List
end

-- ---------------------------------------------------------------------
-- 12) VORSCHAU (ViewportFrames: Willkommen-zurück Vorher/Nachher, Tower-Menü) – ≤ 220 Parts
-- ---------------------------------------------------------------------
function TowerModels.Preview(stage: number, floors: number, skin: string, neon: string, crown: string?): { PartSpec }
	local s = clampStage(stage)
	local count = if finite(floors) then math.clamp(math.floor(floors), 0, FLOORS) else 0
	local list: { PartSpec } = {}
	local pal = TowerModels.Palette(skin, nil)
	local neonHex = TowerModels.NeonHex(neon)
	add(list, { 70, 1, 70 }, { 0, -0.5, 0 }, "#1a2130", "Concrete", { Tag = "Ground" })
	if count <= 0 then
		add(list, { 16, 9, 14 }, { 0, 4.5, 0 }, "#7a4a35", "Brick", { Tag = "Garage" })
		add(list, { 15, 8, 0.4 }, { 0, 4, -7.1 }, "#8b97a8", "CorrodedMetal", { Tag = "RollerDoor" })
		return list
	end
	local look = lookOf(s)
	for _, seg in ipairs(segments(s, count)) do
		local first, last, size = seg[1], seg[2], seg[3]
		local bottom = (first - 1) * FH
		local h = (last - first + 1) * FH
		local body = if s <= 2 then "#c9d2de" elseif s == 3 then "#8a4b32" else pal.Glass
		add(list, { size, h, size }, { 0, bottom + h / 2, 0 }, body, if s <= 3 then "SmoothPlastic" else "Glass", {
			Tag = "Body",
			Transparency = if s <= 3 then 0 else 0.1,
			Reflectance = if s <= 3 then 0 else pal.GlassR,
		})
		if look.Band then
			for f = first, last do
				add(list, { size + 0.8, 0.35, size + 0.8 }, { 0, (f - 1) * FH + 0.5, 0 }, neonHex, "Neon", {
					Tag = "Neon",
					Attr = { Floor = f },
				})
			end
		end
	end
	for _, spec in ipairs(TowerModels.Crown(s, crown or "", count, skin, neon)) do
		local copy = table.clone(spec)
		copy.Pos = { spec.Pos[1], spec.Pos[2] + count * FH, spec.Pos[3] }
		copy.Light = nil
		table.insert(list, copy)
	end
	return list
end

-- ---------------------------------------------------------------------
-- 13) TEILE-BUDGET (§B3: Hülle ≤ 8/Etage, Krone ≤ 60, Plot-Ausstattung ≤ 40; 10 Tower ≤ 4.600)
-- ---------------------------------------------------------------------
function TowerModels.Count(stage: number, floors: number): (number, number, number, number, number)
	local s = clampStage(stage)
	local count = if finite(floors) then math.clamp(math.floor(floors), 0, FLOORS) else 0
	local total, maxFloor = 0, 0
	for f = 1, count do
		local n = #TowerModels.Shell(s, f, DEFAULT_SKIN, "Accent")
		maxFloor = math.max(maxFloor, n)
		total += n
	end
	local spine = #TowerModels.Spine(s, count, DEFAULT_SKIN, "Accent")
	local crown = if count > 0 then #TowerModels.Crown(s, "Orbit", count, DEFAULT_SKIN, "Accent") else 0
	local site = #TowerModels.Site(s, count, DEFAULT_SKIN, "Accent")
	return total + spine + crown + site, maxFloor, spine, crown, site
end

TowerModels.LIMITS = {
	ShellPerFloor = MAX_SHELL_FLOOR,
	Crown = MAX_CROWN,
	Site = MAX_SITE,
	Interior = MAX_INTERIOR,
	TowerTotal = 460,
	AllTowers = 4600,
	LayoutBytes = 2048,
}

-- ---------------------------------------------------------------------
-- 14) LAYOUT-ATTRIBUT (§C12.3): je Etage "Raum:Stufe:Personal:Deko", getrennt durch ";", Privat = Präfix "!"
-- ---------------------------------------------------------------------
function TowerModels.EncodeLayout(floors: { any }, private: { number }?): string
	local privateSet: { [number]: boolean } = {}
	if type(private) == "table" then
		for _, index in ipairs(private) do
			if finite(index) then
				privateSet[math.floor(index)] = true
			end
		end
	end
	local parts: { string } = {}
	for i, floor in ipairs(floors) do
		if i > FLOORS then
			break
		end
		local room = if type(floor) == "table" then floor.R else nil
		local roomCode = ROOM_CODE[room or ""] or ROOM_CODE.Office or "O"
		local level = if type(floor) == "table" and finite(floor.L) then math.clamp(math.floor(floor.L), 1, 5) else 1
		local staff: { string } = {}
		if type(floor) == "table" and type(floor.S) == "table" then
			for _, key in ipairs(floor.S) do
				local code = STAFF_CODE[key]
				if code and #staff < 3 then
					table.insert(staff, code)
				end
			end
		end
		local decor: { string } = {}
		if type(floor) == "table" and type(floor.D) == "table" then
			for slotIndex, key in ipairs(floor.D) do
				if slotIndex > 16 then
					break
				end
				decor[slotIndex] = if type(key) == "string" and DECOR_CODE[key] then DECOR_CODE[key] else ""
			end
			while #decor > 0 and decor[#decor] == "" do
				table.remove(decor)
			end
		end
		local text = ("%s:%d:%s:%s"):format(roomCode, level, table.concat(staff), table.concat(decor, ","))
		if privateSet[i] then
			text = "!" .. text
		end
		parts[i] = text
	end
	return table.concat(parts, ";")
end

function TowerModels.DecodeLayout(text: string): { FloorLayout }
	local out: { FloorLayout } = {}
	if type(text) ~= "string" or text == "" or #text > 4096 then
		return out
	end
	for chunk in string.gmatch(text .. ";", "([^;]*);") do
		if #out >= FLOORS then
			break
		end
		local private = false
		if string.sub(chunk, 1, 1) == "!" then
			private = true
			chunk = string.sub(chunk, 2)
		end
		local roomCode, levelText, staffText, decorText = string.match(chunk, "^(%u?):(%d?):(%u*):([%w,]*)$")
		local entry: FloorLayout = {
			Room = CODE_ROOM[roomCode or ""] or "Office",
			Level = math.clamp(tonumber(levelText) or 1, 1, 5),
			Staff = {},
			Decor = {},
			Private = private,
		}
		if staffText then
			for i = 1, math.min(#staffText, 3) do
				local key = CODE_STAFF[string.sub(staffText, i, i)]
				if key then
					table.insert(entry.Staff, key)
				end
			end
		end
		if decorText and decorText ~= "" then
			local index = 0
			for code in string.gmatch(decorText .. ",", "([^,]*),") do
				index += 1
				if index > 16 then
					break
				end
				entry.Decor[index] = CODE_DECOR[code] or ""
			end
		end
		table.insert(out, entry)
	end
	return out
end

-- ---------------------------------------------------------------------
-- 15) ROBLOX: PartSpec -> BasePart (nur in Roblox aufrufen; Farben/Materialien gecacht)
-- ---------------------------------------------------------------------
local colorCache: { [string]: any } = {}
local materialCache: { [string]: any } = {}

local function colorOf(hex: string): any
	local cached = colorCache[hex]
	if cached then
		return cached
	end
	local r, g, b = TowerModels.Hex(hex)
	local value = (Color3 :: any).fromRGB(r, g, b)
	colorCache[hex] = value
	return value
end

local function materialOf(name: string): any
	local cached = materialCache[name]
	if cached then
		return cached
	end
	local ok, value = pcall(function()
		return ((Enum :: any).Material :: any)[name]
	end)
	local material = if ok and value then value else (Enum :: any).Material.SmoothPlastic
	materialCache[name] = material
	return material
end

function TowerModels.KindOf(spec: PartSpec): string
	if spec.Kind == "Wedge" then
		return "WedgePart"
	elseif spec.Kind == "CornerWedge" then
		return "CornerWedgePart"
	end
	return "Part"
end

local function offsetCFrame(spec: PartSpec): any
	local cf = (CFrame :: any).new(spec.Pos[1], spec.Pos[2], spec.Pos[3])
	local rot = spec.Rot
	if rot then
		cf = cf * (CFrame :: any).fromOrientation(math.rad(rot[1] or 0), math.rad(rot[2] or 0), math.rad(rot[3] or 0))
	end
	return cf
end

TowerModels.OffsetCFrame = offsetCFrame

-- Eigenschaften auf ein (evtl. wiederverwendetes) Part schreiben; origin = CFrame des Bezugspunkts
function TowerModels.Apply(part: any, spec: PartSpec, origin: any)
	if part:IsA("Part") then
		local shape = spec.Shape
		part.Shape = if shape == "Cylinder"
			then (Enum :: any).PartType.Cylinder
			elseif shape == "Ball" then (Enum :: any).PartType.Ball
			else (Enum :: any).PartType.Block
	end
	part.Size = (Vector3 :: any).new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.CFrame = origin * offsetCFrame(spec)
	part.Color = colorOf(spec.Color)
	part.Material = materialOf(spec.Material)
	part.Transparency = spec.Transparency or 0
	part.Reflectance = spec.Reflectance or 0
	part.CanCollide = spec.Collide == true
	part.CanQuery = spec.Query == true or spec.Collide == true
	part.CanTouch = false
	part.CastShadow = spec.Shadow ~= false and (spec.Transparency or 0) < 0.5
	part.Anchored = true
	part.Massless = true
	part.TopSurface = (Enum :: any).SurfaceType.Smooth
	part.BottomSurface = (Enum :: any).SurfaceType.Smooth
	part.Name = spec.Name or spec.Tag or "Part"
	local light = spec.Light
	if light then
		local className = if light.Kind == "Spot"
			then "SpotLight"
			elseif light.Kind == "Surface" then "SurfaceLight"
			else "PointLight"
		local inst = (Instance :: any).new(className)
		inst.Range = light.Range
		inst.Brightness = light.Brightness
		inst.Color = colorOf(light.Color)
		inst.Shadows = false
		if className ~= "PointLight" then
			pcall(function()
				inst.Face = ((Enum :: any).NormalId :: any)[light.Face or "Front"]
				inst.Angle = light.Angle or 60
			end)
		end
		inst.Parent = part
	end
	if spec.Tag then
		part:SetAttribute("Tag", spec.Tag)
	end
	if spec.Group then
		part:SetAttribute("Group", spec.Group)
	end
	if spec.Anim then
		part:SetAttribute("Anim", spec.Anim)
	end
	local attrs = spec.Attr
	if attrs then
		for key, value in pairs(attrs) do
			part:SetAttribute(key, value)
		end
	end
end

function TowerModels.Instantiate(spec: PartSpec, origin: any, parent: any?): any
	local part = (Instance :: any).new(TowerModels.KindOf(spec))
	TowerModels.Apply(part, spec, origin)
	if parent then
		part.Parent = parent
	end
	return part
end

-- ---------------------------------------------------------------------
-- 16) START: in Roblox Config.Tower + Config.Decor übernehmen (Luau-CLI: "script" fehlt -> Startwerte)
-- ---------------------------------------------------------------------
do
	local ok, towerCfg, decorCfg = pcall(function(): (any, any)
		local here: any = script
		if typeof(here) ~= "Instance" then
			return nil, nil
		end
		local configModule = here.Parent and here.Parent:FindFirstChild("Config")
		local function load(name: string): any
			local module = configModule and configModule:FindFirstChild(name)
			if module and module:IsA("ModuleScript") then
				local loaded, result = pcall(require, module)
				return if loaded then result else nil
			end
			return nil
		end
		return load("Tower"), load("Decor")
	end)
	if ok then
		TowerModels.Configure(towerCfg, decorCfg)
	end
end

return TowerModels
