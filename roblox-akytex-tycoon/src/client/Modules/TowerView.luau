-- =====================================================================
--  AKYTEX TYCOON – Tower-Ansicht: Interiors, Fensterlichter, Kräne, Plot-Schilder (Client/Modules/TowerView)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §B3 (Client baut Interiors aus dem Plot-
--  Attribut "Layout": nur für den Tower, in dem man ist oder < 80 Studs davor, Etagen ±k um die Kamera (k je
--  Grafikstufe 0/1/2/4 = Quality.Budget("InteriorRadius")), ≤ 150 Parts je Etage aus Pools, Aufbau ≤ 1,5 ms je Frame;
--  andere Tower zeigen beleuchtete Fenster/Neon-Streifen), §A4 (Fensterlicht-Kaskade ab ClockTime 18,5 von unten
--  nach oben, 0,05 s je Etage), §B4.4 (Roboter-Wippen/Kopfdrehen im einen PreRender-Loop, nur nahe Etagen),
--  §B4.6 (Kassen-Tor), §B4.7 (Kran + Bau-Hilfe), §B4.9 (Fassaden-LED zeigt AKX36-Farbe, nie eigenes G/V; Neon-
--  Fassaden-Kit: 8 Lichtmuster nachts), §B4.10 (Aufzugstür -> Etagen-Panel, Privat-Etagen), §B11.3 (Respekt-Säule),
--  §C16 (TowerView < 0,3 ms/Frame), Muss-Regel 16 (StreamingEnabled: alles nil-sicher, Teile kommen und gehen).
--
--  Liest: Workspace.AkyTowers.Plot<n> (Attribute von TowerVisualService), State Plot/Tower, Quality-Budgets.
--  Live-Monitore: Interior-Monitore tragen das Attribut "Monitor" (WP5-Monitors rendert die nächsten K live).
--  Hooks: feuert "Plot:Enter" / "Plot:Leave" (plotId, ownerUserId).
--  Ein PreRender-Loop: TowerView.Frame(dt) (FRAME_MODULES) treibt auch EffectsTower.Step, Elevator.Step und
--  Boutique.Step an (diese Module stehen nicht in FRAME_MODULES – so bleibt es bei EINEM Loop, Muss-Regel 2).
--
--  Öffentliche API (§C7.5):
--    TowerView.InsideTower(): number?            Plot, in dessen Tower-Grundriss die eigene Figur steht
--  Ergänzungen (für EffectsTower/Elevator/TowerUI/WelcomeBack):
--    TowerView.ActivePlot(): number?   TowerView.OwnPlot(): number?   TowerView.PlotFolder(plot): Folder?
--    TowerView.PlotInfo(plot): { Pivot, Stage, Floors, Owner, Name, Layout }?   TowerView.TowerModel(plot): Model?
--    TowerView.FloorOf(position: Vector3, plot): number    TowerView.CurrentFloor(): number?
--    TowerView.FloorCFrame(plot, floor): CFrame?  (Füße vor der Aufzugstür)   TowerView.TopCFrame(plot): CFrame?
--    TowerView.ShowCrane(plot, floor, seconds)    TowerView.CraneHook(plot): BasePart?   TowerView.NeonBands(plot)
--    TowerView.Frame(dt), TowerView.Init(ctx), TowerView.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerModels = require(Shared:WaitForChild("TowerModels"))
require(Shared:WaitForChild("DecorModels")) -- registriert sich bei TowerModels als Deko-Lieferant

local TowerView = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local FOLDER_NAME = "AkyTowers"
local ACTIVE_RANGE = 80 -- §B3: Interiors für den Tower, in dem man ist oder < 80 Studs davor
local BUILD_BUDGET = 0.0015 -- §B3/§C16: Aufbau ≤ 1,5 ms je Frame
local POOL_MAX = 900
local ANIM_RANGE = 70 -- Roboter/Deko-Animation nur nah
local CROWN_RANGE = 650 -- Kronen-Animation (Leuchtfeuer, Holo-Ringe) nur in Sichtweite
local NIGHT_STEP = 0.05 -- §A4: Fensterlicht-Kaskade 0,05 s je Etage
local GATE_GAP = 2 -- Sekunden zwischen zwei Kassen-Tor-Anfragen
local LED_GAP = 2 -- Sekunden: Fassaden-LED (AKX36) auffrischen
local FX_PERIOD = 20 -- Sekunden je Lichtmuster (Neon-Fassaden-Kit, 8 Muster)
local AKX36 = 40
local MAX_PLOTS = 32

type AnimGroup = {
	Kind: string,
	Parts: { BasePart },
	Base: { CFrame },
	Heads: { [number]: boolean },
	HeadCenter: Vector3?,
	Center: Vector3,
	Top: number,
	Phase: number,
}

type FloorBuild = {
	Floor: number,
	Sig: string,
	Parts: { BasePart },
	Groups: { AnimGroup },
	Lights: { Light },
	Door: BasePart?,
	Doors: { { Part: BasePart, Base: CFrame, Side: number } }?,
}

type PlotInfo = {
	Plot: number,
	Folder: Folder,
	Pivot: CFrame,
	Owner: number,
	Stage: number,
	Floors: number,
	Layout: string,
	Chunks: { string },
	Model: Model?,
	Bands: { BasePart },
	Leds: { BasePart },
	Anim: { AnimGroup },
	Sign: BasePart?,
	VaultRing: BasePart?,
	Respekt: BasePart?,
	Panel: BasePart?,
	ScanDirty: boolean,
	NightLit: number, -- so viele Etagen leuchten schon (Kaskade)
	Fx: boolean,
	Crane: { BasePart }?,
	CraneHook: BasePart?,
	CraneFloor: number,
	CraneUntil: number,
	Conns: { RBXScriptConnection },
	ModelConns: { RBXScriptConnection },
	Fading: { { Model: Model, Start: number, Seconds: number, Last: number } },
}

local ctx: any = nil
local interiorFolder: Folder? = nil
local plots: { [number]: PlotInfo } = {}
local active: number? = nil
local activeOwner = 0
local built: { [number]: FloorBuild } = {}
local builtPlot: number? = nil
local builtStage = 0
local queue: { number } = {}
local pools: { [string]: { BasePart } } = { Part = {}, WedgePart = {}, CornerWedgePart = {} }
local prompt: ProximityPrompt? = nil
local respektPrompt: ProximityPrompt? = nil
local helpPrompt: ProximityPrompt? = nil
local night = false
local nightStart = 0
local gateAt = 0
local ledAt = 0
local clock = 0
local lightBudget = 0
local signLang = ""
local uiTick = 0

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

-- Gemeinsame Prompts (Aufzug, Respekt, Bau-Hilfe) wandern zwischen Teilen, die gepoolt (ClearAllChildren), vom Server
-- neu gebaut oder herausgestreamt werden – dabei würde der Prompt mit zerstört (Parent gesperrt). placePrompt hängt
-- ihn sicher um und baut ihn bei Bedarf neu, damit Aufzug/Respekt/Bau-Hilfe nie dauerhaft ausfallen.
local PROMPT_DEFS: { [string]: { Name: string, Key: string, Distance: number } } = {
	Elevator = { Name = "AkyElevator", Key = "tui.elevator.prompt", Distance = 10 },
	Respekt = { Name = "AkyRespekt", Key = "tui.respekt.prompt", Distance = 12 },
	Help = { Name = "AkyHelp", Key = "tui.help.prompt", Distance = 40 },
}

local function makePrompt(name: string, actionKey: string, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = T(actionKey)
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = distance
	p.HoldDuration = 0
	p.Style = Enum.ProximityPromptStyle.Default
	return p
end

local function promptVar(kind: string): ProximityPrompt?
	return if kind == "Elevator" then prompt elseif kind == "Respekt" then respektPrompt else helpPrompt
end

local function placePrompt(kind: string, target: Instance?): ProximityPrompt?
	local current = promptVar(kind)
	if current and current.Parent == target then
		return current
	end
	local moved = current ~= nil and pcall(function()
		(current :: ProximityPrompt).Parent = target
	end)
	if moved then
		return current
	end
	local def = PROMPT_DEFS[kind]
	if not def then
		return nil
	end
	local fresh = makePrompt(def.Name, def.Key, def.Distance)
	fresh.Parent = target
	if kind == "Elevator" then
		prompt = fresh
	elseif kind == "Respekt" then
		respektPrompt = fresh
	else
		helpPrompt = fresh
	end
	return fresh
end

local function budget(key: string, default: number): number
	local ok, value = call("Quality", "Budget", key)
	return if ok and type(value) == "number" then value else default
end

local function rootPart(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function focusPosition(): Vector3?
	local part = rootPart()
	if part then
		return part.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

local function ownPlot(): number?
	local state = ctx and ctx.State
	local plot = state and state.Plot
	local id = if type(plot) == "table" then plot.Id else nil
	if type(id) == "number" and id >= 1 then
		return id
	end
	local attr = player:GetAttribute("Plot")
	return if type(attr) == "number" and attr >= 1 then attr else nil
end

local FH = TowerModels.FloorHeight()
local SLAB = TowerModels.SlabHeight()

local function floorCFrame(info: PlotInfo, floor: number): CFrame
	return info.Pivot * CFrame.new(0, (floor - 1) * FH + SLAB, 0)
end

local function horizontal(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- ---------------------------------------------------------------------
-- 2) POOLS (gleiche Part-Klassen werden weitergereicht – kein Instance.new beim Laufen)
-- ---------------------------------------------------------------------
local function acquire(className: string): BasePart
	local pool = pools[className]
	local part = pool and table.remove(pool)
	if part then
		return part
	end
	return Instance.new(className) :: BasePart
end

local function release(part: BasePart)
	part.Parent = nil
	part:ClearAllChildren()
	for name in pairs(part:GetAttributes()) do
		part:SetAttribute(name, nil)
	end
	part.LocalTransparencyModifier = 0
	local pool = pools[part.ClassName]
	if pool and #pool < POOL_MAX then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

-- ---------------------------------------------------------------------
-- 3) ANIMATIONS-GRUPPEN (Roboter wippen, Köpfe drehen, Globen kreisen, Fische schwimmen …)
-- ---------------------------------------------------------------------
local function makeGroups(parts: { BasePart }): { AnimGroup }
	local byKey: { [string]: AnimGroup } = {}
	local list: { AnimGroup } = {}
	for _, part in ipairs(parts) do
		local anim = part:GetAttribute("Anim")
		if type(anim) == "string" then
			local key = tostring(part:GetAttribute("Group") or anim) .. ":" .. (if anim == "Head" then "Bob" else anim)
			local group = byKey[key]
			if not group then
				group = {
					Kind = if anim == "Head" then "Bob" else anim,
					Parts = {},
					Base = {},
					Heads = {},
					HeadCenter = nil,
					Center = Vector3.zero,
					Top = -math.huge,
					Phase = (#list * 1.37) % (math.pi * 2),
				}
				byKey[key] = group
				table.insert(list, group)
			end
			table.insert(group.Parts, part)
			table.insert(group.Base, part.CFrame)
			if anim == "Head" then
				group.Heads[#group.Parts] = true
			end
		end
	end
	for _, group in ipairs(list) do
		local sum, headSum, heads = Vector3.zero, Vector3.zero, 0
		for i, part in ipairs(group.Parts) do
			sum += part.Position
			group.Top = math.max(group.Top, part.Position.Y + part.Size.Y / 2)
			if group.Heads[i] then
				headSum += part.Position
				heads += 1
			end
		end
		group.Center = sum / math.max(1, #group.Parts)
		if heads > 0 then
			group.HeadCenter = headSum / heads
		end
	end
	return list
end

local animParts: { BasePart } = {}
local animCFrames: { CFrame } = {}

local function stepGroup(group: AnimGroup, t: number)
	local kind = group.Kind
	local ph = group.Phase
	if kind == "Beacon" then
		local alpha = 0.5 + 0.5 * math.sin(t * 3 + ph)
		for _, part in ipairs(group.Parts) do
			part.Transparency = alpha * 0.7
		end
		return
	end
	local c = group.Center
	local around: CFrame? = nil
	local offset = Vector3.zero
	local headYaw = 0
	if kind == "Bob" then
		offset = Vector3.new(0, math.sin(t * 2.2 + ph) * 0.12, 0)
		headYaw = math.sin(t * 0.9 + ph) * 0.45
	elseif kind == "Spin" then
		around = CFrame.new(c) * CFrame.Angles(0, (t * 0.8 + ph) % (math.pi * 2), 0) * CFrame.new(-c)
	elseif kind == "Sweep" or kind == "Arm" then
		around = CFrame.new(c)
			* CFrame.Angles(0, math.sin(t * 0.6 + ph) * (if kind == "Arm" then 0.9 else 1.0), 0)
			* CFrame.new(-c)
	elseif kind == "Fish" then
		local a = t * 0.9 + ph
		offset = Vector3.new(math.cos(a) * 0.5, math.sin(t * 2 + ph) * 0.08, math.sin(a) * 0.3)
	elseif kind == "Swing" then
		local pivot = Vector3.new(c.X, group.Top, c.Z)
		around = CFrame.new(pivot) * CFrame.Angles(math.sin(t * 1.8 + ph) * 0.22, 0, 0) * CFrame.new(-pivot)
	elseif kind == "Lift" then
		offset = Vector3.new(0, (math.sin(t * 0.5 + ph) + 1) * 0.12, 0)
	elseif kind == "Patrol" then
		offset = Vector3.new(math.sin(t * 0.35 + ph) * 4, math.sin(t * 2.2) * 0.1, 0)
	else
		return
	end
	for i, part in ipairs(group.Parts) do
		local base = group.Base[i]
		local cf = if around then around * base else base + offset
		local hc = group.HeadCenter
		if group.Heads[i] and hc and headYaw ~= 0 then
			cf = CFrame.new(hc + offset) * CFrame.Angles(0, headYaw, 0) * CFrame.new(-hc) * base
		end
		table.insert(animParts, part)
		table.insert(animCFrames, cf)
	end
end

-- ---------------------------------------------------------------------
-- 4) INTERIORS (Etagen ±k, Pools, Zeitbudget)
-- ---------------------------------------------------------------------
local function releaseFloor(floor: number)
	local build = built[floor]
	if not build then
		return
	end
	built[floor] = nil
	-- Aufzugs-Prompt VOR dem Poolen abhängen (release räumt alle Kinder weg = würde ihn zerstören)
	if prompt and build.Door and prompt.Parent == build.Door then
		placePrompt("Elevator", nil)
	end
	for _, part in ipairs(build.Parts) do
		release(part)
	end
end

local function releaseAll()
	for floor in pairs(built) do
		releaseFloor(floor)
	end
	table.clear(queue)
	builtPlot = nil
end

local function chunkOf(info: PlotInfo, floor: number): string
	return info.Chunks[floor] or ""
end

local function lobbyRobots(info: PlotInfo): { any }
	local list: { any } = {}
	local lobby = info.Folder:GetAttribute("Lobby")
	if type(lobby) ~= "string" or lobby == "" then
		return list
	end
	local inner = TowerModels.Footprint(info.Stage, 1) / 2 - 1.4
	if string.find(lobby, "J", 1, true) then
		for _, spec in ipairs(TowerModels.Robot("Janitor", inner * 0.35, inner * 0.6, 180, "Janitor")) do
			table.insert(list, spec)
		end
	end
	if string.find(lobby, "W", 1, true) then
		for _, spec in ipairs(TowerModels.Robot("Security", inner * 0.38, -inner * 0.42, 0, "Security")) do
			local copy = table.clone(spec)
			copy.Anim = if spec.Anim == "Head" then "Head" else "Patrol"
			table.insert(list, copy)
		end
	end
	return list
end

local function buildFloor(info: PlotInfo, floor: number)
	local chunk = chunkOf(info, floor)
	local entries = TowerModels.DecodeLayout(chunk)
	local entry = entries[1]
	local folder = interiorFolder
	if not folder then
		return
	end
	local owner = info.Owner == player.UserId
	local specs: { any }
	if entry and entry.Private and not owner then
		specs = {} -- Privat-Etage: für Besucher nicht einsehbar
	else
		local room = if entry then entry.Room else "Office"
		local level = if entry then entry.Level else 1
		local staff = if entry then entry.Staff else {}
		local decor = if entry then entry.Decor else {}
		specs = TowerModels.Interior(room, level, staff, decor, TowerModels.Footprint(info.Stage, floor), floor)
	end
	if floor == 1 then
		for _, spec in ipairs(lobbyRobots(info)) do
			table.insert(specs, spec)
		end
	end
	local origin = floorCFrame(info, floor)
	local build: FloorBuild =
		{ Floor = floor, Sig = chunk .. "|" .. tostring(info.Stage), Parts = {}, Groups = {}, Lights = {}, Door = nil }
	for _, spec in ipairs(specs) do
		local part = acquire(TowerModels.KindOf(spec))
		TowerModels.Apply(part, spec, origin)
		part.CanQuery = false
		part.Parent = folder
		table.insert(build.Parts, part)
		local light = part:FindFirstChildWhichIsA("Light")
		if light then
			light.Enabled = false
			table.insert(build.Lights, light)
		end
		if spec.Tag == "ElevatorFrame" then
			build.Door = part
		elseif spec.Tag == "ElevatorDoor" then
			-- Türflügel merken: der Aufzug öffnet/schließt sie lokal mit der Kabine (Elevator.Step)
			local doors = build.Doors or {}
			build.Doors = doors
			table.insert(doors, { Part = part, Base = part.CFrame, Side = if spec.Group == "DoorL" then -1 else 1 })
		end
	end
	build.Groups = makeGroups(build.Parts)
	built[floor] = build
end

-- Welche Etagen sollen stehen? Aktueller Stock ± k (k aus der Grafikstufe)
local function wantedFloors(info: PlotInfo, current: number): { [number]: boolean }
	local k = math.clamp(math.floor(budget("InteriorRadius", 1)), 0, 6)
	local wanted: { [number]: boolean } = {}
	if info.Floors <= 0 then
		return wanted
	end
	for f = math.max(1, current - k), math.min(info.Floors, current + k) do
		wanted[f] = true
	end
	wanted[math.clamp(current, 1, info.Floors)] = true
	return wanted
end

local function currentFloor(info: PlotInfo): number
	local pos = focusPosition()
	if not pos then
		return 1
	end
	local localPos = info.Pivot:PointToObjectSpace(pos)
	return math.clamp(math.floor((localPos.Y - 0.5) / FH) + 1, 1, math.max(1, info.Floors))
end

local interiorLightsOn = 0 -- WorldLook zieht sie vom Licht-Budget der Stadt ab (Summe bleibt ≤ Budget je Stufe)

local function updateLights(current: number)
	local cap = math.max(2, math.floor(lightBudget / 2))
	local used = 0
	for floor, build in pairs(built) do
		local near = math.abs(floor - current) <= 1
		for _, light in ipairs(build.Lights) do
			local on = near and used < cap
			if on then
				used += 1
			end
			if light.Enabled ~= on then
				light.Enabled = on
			end
		end
	end
	interiorLightsOn = used
end

local function processInteriors(info: PlotInfo?)
	if not info or info.Floors <= 0 then
		if builtPlot then
			releaseAll()
		end
		interiorLightsOn = 0
		return
	end
	if builtPlot ~= info.Plot or builtStage ~= info.Stage then
		releaseAll()
		builtPlot = info.Plot
		builtStage = info.Stage
	end
	local current = currentFloor(info)
	local wanted = wantedFloors(info, current)
	-- nicht mehr gewollt oder veraltet -> zurück in den Pool
	for floor, build in pairs(built) do
		if not wanted[floor] or build.Sig ~= chunkOf(info, floor) .. "|" .. tostring(info.Stage) then
			releaseFloor(floor)
		end
	end
	-- fehlende Etagen in die Warteschlange (nächste zuerst)
	table.clear(queue)
	for floor in pairs(wanted) do
		if not built[floor] then
			table.insert(queue, floor)
		end
	end
	table.sort(queue, function(a, b)
		return math.abs(a - current) < math.abs(b - current)
	end)
	local started = os.clock()
	while #queue > 0 and os.clock() - started < BUILD_BUDGET do
		local floor = table.remove(queue, 1) :: number
		local ok, err = pcall(buildFloor, info, floor)
		if not ok then
			warn("[TowerView] Etage " .. floor .. ": " .. tostring(err))
			built[floor] = {
				Floor = floor,
				Sig = chunkOf(info, floor) .. "|" .. tostring(info.Stage),
				Parts = {},
				Groups = {},
				Lights = {},
			}
		end
	end
	updateLights(current)
	-- Aufzugs-Panel-Knopf an der Tür des aktuellen Stocks (EG zusätzlich am Lobby-Panel)
	local build = built[current]
	local target: Instance? = if build and build.Door then build.Door elseif current == 1 then info.Panel else nil
	local p = placePrompt("Elevator", target)
	if p and p.Parent then
		p.ObjectText = T("tui.floorLabel", current)
	end
end

-- ---------------------------------------------------------------------
-- 5) PLOTS: Attribute, Hülle (Server-Teile), Schild, LED, Fensterlichter
-- ---------------------------------------------------------------------
local function splitLayout(text: string): { string }
	local chunks: { string } = {}
	if text == "" then
		return chunks
	end
	for chunk in string.gmatch(text .. ";", "([^;]*);") do
		table.insert(chunks, chunk)
		if #chunks >= 50 then
			break
		end
	end
	return chunks
end

local function towerNameText(info: PlotInfo): string
	local raw = info.Folder:GetAttribute("Name")
	local a, n = 1, 1
	if type(raw) == "string" then
		local sa, sn = string.match(raw, "^(%d+):(%d+)$")
		a, n = tonumber(sa) or 1, tonumber(sn) or 1
	end
	local towerCfg = ctx.Config.Tower
	if type(towerCfg) == "table" and type(towerCfg.NameText) == "function" then
		local ok, text = pcall(towerCfg.NameText, a, n, lang())
		if ok and type(text) == "string" then
			return text
		end
	end
	return T("tui.title")
end

local function licenceName(index: number): string
	local progression = ctx.Config.Progression
	local list = if type(progression) == "table" then progression.Licences else nil
	local entry = if type(list) == "table" then list[index] else nil
	if type(entry) == "table" and type(entry.Name) == "table" then
		return ctx.Lang.Pick(lang(), entry.Name)
	end
	return T("tui.licenceLevel", index)
end

-- Plot-Schild: Besitzer, Tower-Name (Wortbausteine, lokalisiert), Lizenz, Titel
local function refreshSign(info: PlotInfo)
	local part = info.Sign
	if not part or part.Parent == nil then
		return
	end
	local gui = part:FindFirstChild("AkySign") :: SurfaceGui?
	if not gui then
		local created = Instance.new("SurfaceGui")
		created.Name = "AkySign"
		created.Face = Enum.NormalId.Front
		created.LightInfluence = 0
		created.Brightness = 1.6
		created.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		created.PixelsPerStud = 40
		created.MaxDistance = 220
		local frame = UI.Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = 0.05,
			Parent = created,
		}, { UI.Create("UIStroke", { Color = Theme.Accent, Thickness = 3, Transparency = 0.3 }) })
		UI.Label({
			Name = "Owner",
			Position = UDim2.fromScale(0.05, 0.06),
			Size = UDim2.fromScale(0.9, 0.3),
			Face = "Display",
			TextColor3 = Theme.Text,
			MaxText = 60,
			Parent = frame,
		})
		UI.Label({
			Name = "Tower",
			Position = UDim2.fromScale(0.05, 0.38),
			Size = UDim2.fromScale(0.9, 0.24),
			TextColor3 = Theme.Accent,
			MaxText = 48,
			Parent = frame,
		})
		UI.Label({
			Name = "Meta",
			Position = UDim2.fromScale(0.05, 0.66),
			Size = UDim2.fromScale(0.9, 0.26),
			TextColor3 = Theme.Text2,
			MaxText = 36,
			Parent = frame,
		})
		created.Parent = part
		gui = created
	end
	local g = gui :: SurfaceGui
	local frame = g:FindFirstChildOfClass("Frame")
	if not frame then
		return
	end
	local ownerLabel = frame:FindFirstChild("Owner") :: TextLabel?
	local towerLabel = frame:FindFirstChild("Tower") :: TextLabel?
	local metaLabel = frame:FindFirstChild("Meta") :: TextLabel?
	local ownerName = info.Folder:GetAttribute("OwnerName")
	local owner = if info.Owner > 0 then Players:GetPlayerByUserId(info.Owner) else nil
	if ownerLabel then
		ownerLabel.Text = if type(ownerName) == "string" and ownerName ~= "" then ownerName else T("tui.plotFree")
	end
	if towerLabel then
		towerLabel.Text = if info.Owner > 0 then towerNameText(info) else ""
	end
	if metaLabel then
		local parts: { string } = {}
		local licence = owner and owner:GetAttribute("Licence")
		if type(licence) == "number" then
			table.insert(parts, licenceName(licence))
		end
		local title = owner and owner:GetAttribute("Title")
		if type(title) == "string" and title ~= "" then
			table.insert(parts, title)
		end
		if info.Owner > 0 then
			table.insert(parts, T("tui.floorsShort", info.Floors))
		end
		metaLabel.Text = table.concat(parts, "  ·  ")
	end
end

-- Fassaden-LED: AKX36-Tagesfarbe (nie das eigene G/V, §B4.9)
local function refreshLeds(info: PlotInfo)
	if #info.Leds == 0 then
		return
	end
	local ok, close, change = call("MarketClient", "Quote", AKX36)
	local delta = if ok and type(change) == "number" then change else 0
	local color = if delta > 0 then UI.UpColor() elseif delta < 0 then UI.DownColor() else Theme.Accent
	local arrow = UI.TrendArrow(delta)
	local pctText = ""
	if ok and type(close) == "number" and close > 0 then
		local fraction = delta / math.max(1, close - delta)
		local okPct, text = pcall(ctx.Format.Pct, fraction, lang(), 2, true)
		pctText = if okPct then text else ""
	end
	for _, part in ipairs(info.Leds) do
		if part.Parent then
			part.Color = color
			part.Material = Enum.Material.Neon
			local gui = part:FindFirstChild("AkyLed") :: SurfaceGui?
			if not gui then
				local created = Instance.new("SurfaceGui")
				created.Name = "AkyLed"
				local face = part:GetAttribute("Face")
				created.Face = if type(face) == "string" and (Enum.NormalId :: any)[face]
					then (Enum.NormalId :: any)[face]
					else Enum.NormalId.Front
				created.LightInfluence = 0
				created.Brightness = 2
				created.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				created.PixelsPerStud = 12
				created.MaxDistance = 600
				UI.Label({
					Name = "Text",
					Size = UDim2.fromScale(1, 1),
					Face = "Display",
					TextColor3 = Color3.new(1, 1, 1),
					MaxText = 120,
					Parent = created,
				})
				created.Parent = part
				gui = created
			end
			local label = (gui :: SurfaceGui):FindFirstChild("Text") :: TextLabel?
			if label then
				label.Text = ("AKX36  %s  %s"):format(arrow, pctText)
			end
		end
	end
end

local function scanModel(info: PlotInfo)
	info.ScanDirty = false
	table.clear(info.Bands)
	table.clear(info.Leds)
	table.clear(info.Anim)
	info.Sign, info.VaultRing, info.Respekt, info.Panel = nil, nil, nil, nil
	info.NightLit = 0
	local model = info.Model
	if not model or model.Parent == nil then
		return
	end
	local animated: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local tag = d:GetAttribute("Tag")
			if tag == "Neon" and d:GetAttribute("Floor") ~= nil then
				table.insert(info.Bands, d)
			end
			if d:GetAttribute("Led") == true then
				table.insert(info.Leds, d)
			end
			if d:GetAttribute("PlotSign") == true then
				info.Sign = d
			elseif d:GetAttribute("VaultRing") == true then
				info.VaultRing = d
			elseif d:GetAttribute("Respekt") == true then
				info.Respekt = d
			elseif d:GetAttribute("ElevatorPanel") == true then
				info.Panel = d
			end
			if d:GetAttribute("Anim") ~= nil then
				table.insert(animated, d)
			end
		end
	end
	table.sort(info.Bands, function(a, b)
		return num(a:GetAttribute("Floor"), 0) < num(b:GetAttribute("Floor"), 0)
	end)
	info.Anim = makeGroups(animated)
	refreshSign(info)
	refreshLeds(info)
	-- neue Hülle (Neubau/Morph/Streaming): Respekt-Knopf an die neue Säule hängen
	if info.Plot == active then
		local target = if info.Owner > 0 and info.Owner ~= player.UserId then info.Respekt else nil
		placePrompt("Respekt", target)
	end
end

local function attachModel(info: PlotInfo, model: Model)
	for _, conn in ipairs(info.ModelConns) do
		conn:Disconnect()
	end
	table.clear(info.ModelConns)
	info.Model = model
	info.ScanDirty = true
	table.insert(
		info.ModelConns,
		model.DescendantAdded:Connect(function()
			info.ScanDirty = true
		end)
	)
	table.insert(
		info.ModelConns,
		model.DescendantRemoving:Connect(function()
			info.ScanDirty = true
		end)
	)
end

-- Alte Hülle blendet aus (Morph/Abbau): der Server benennt die VORHANDENE Hülle um und setzt "Fading" – das kommt
-- als Attribut-Änderung, nicht als ChildAdded an (nur hereingestreamte Hüllen tragen es schon beim Einhängen).
local function startFade(info: PlotInfo, model: Model)
	for _, entry in ipairs(info.Fading) do
		if entry.Model == model then
			return
		end
	end
	if info.Model == model then
		info.Model = nil
		info.ScanDirty = true
		for _, conn in ipairs(info.ModelConns) do
			conn:Disconnect()
		end
		table.clear(info.ModelConns)
	end
	local seconds = num(model:GetAttribute("FadeSeconds"), 2)
	table.insert(info.Fading, { Model = model, Start = os.clock(), Seconds = math.clamp(seconds, 0.3, 5), Last = 0 })
end

local function onModelAdded(info: PlotInfo, child: Instance)
	if not child:IsA("Model") then
		return
	end
	if child:GetAttribute("Fading") == true then
		startFade(info, child)
	elseif child.Name == "Tower" then
		attachModel(info, child)
		call("EffectsTower", "OnTowerModel", info.Plot, child)
		-- eigene Verbindung (nicht ModelConns: die trennt attachModel der NEUEN Hülle schon vorher)
		child:GetAttributeChangedSignal("Fading"):Once(function()
			if child.Parent ~= nil and child:GetAttribute("Fading") == true then
				startFade(info, child)
			end
		end)
	end
end

local function readAttributes(info: PlotInfo)
	local f = info.Folder
	local pivot = f:GetAttribute("Pivot")
	if typeof(pivot) == "CFrame" then
		info.Pivot = pivot
	end
	info.Owner = math.floor(num(f:GetAttribute("Owner"), 0))
	info.Stage = math.clamp(math.floor(num(f:GetAttribute("Stage"), 1)), 1, 12)
	info.Floors = math.clamp(math.floor(num(f:GetAttribute("Floors"), 0)), 0, 50)
	local layout = f:GetAttribute("Layout")
	info.Layout = if type(layout) == "string" then layout else ""
	info.Chunks = splitLayout(info.Layout)
	info.Fx = f:GetAttribute("Fx") == true
end

local function ensurePlot(folder: Instance)
	if not folder:IsA("Folder") then
		return
	end
	local plot = folder:GetAttribute("Plot")
	if type(plot) ~= "number" then
		plot = tonumber(string.match(folder.Name, "^Plot(%d+)$"))
	end
	if type(plot) ~= "number" or plot < 1 or plot > MAX_PLOTS or plots[plot] then
		return
	end
	local info: PlotInfo = {
		Plot = plot,
		Folder = folder :: Folder,
		Pivot = CFrame.identity,
		Owner = 0,
		Stage = 1,
		Floors = 0,
		Layout = "",
		Chunks = {},
		Model = nil,
		Bands = {},
		Leds = {},
		Anim = {},
		Sign = nil,
		VaultRing = nil,
		Respekt = nil,
		Panel = nil,
		ScanDirty = false,
		NightLit = 0,
		Fx = false,
		Crane = nil,
		CraneHook = nil,
		CraneFloor = 0,
		CraneUntil = 0,
		Conns = {},
		ModelConns = {},
		Fading = {},
	}
	plots[plot] = info
	readAttributes(info)
	table.insert(
		info.Conns,
		folder.AttributeChanged:Connect(function(name: string)
			local oldOwner = info.Owner
			readAttributes(info)
			if name == "Owner" and oldOwner ~= info.Owner and info.Owner == 0 then
				call("EffectsTower", "Teardown", info.Plot)
			end
			if name == "Owner" or name == "OwnerName" or name == "Name" or name == "Floors" then
				refreshSign(info)
			end
		end)
	)
	table.insert(
		info.Conns,
		folder.ChildAdded:Connect(function(child: Instance)
			onModelAdded(info, child)
		end)
	)
	table.insert(
		info.Conns,
		folder.ChildRemoved:Connect(function(child: Instance)
			if info.Model == child then
				info.Model = nil
				info.ScanDirty = true
			end
		end)
	)
	for _, child in ipairs(folder:GetChildren()) do
		onModelAdded(info, child)
	end
end

local function watchRoot()
	task.spawn(function()
		local folder = workspace:WaitForChild(FOLDER_NAME, 60)
		if not folder or not folder:IsA("Folder") then
			warn("[TowerView] " .. FOLDER_NAME .. " fehlt – keine Tower-Ansicht")
			return
		end
		for _, child in ipairs(folder:GetChildren()) do
			ensurePlot(child)
		end
		folder.ChildAdded:Connect(ensurePlot)
	end)
end

-- ---------------------------------------------------------------------
-- 6) FENSTERLICHTER (Kaskade von unten nach oben) + Neon-Fassaden-Kit-Muster
-- ---------------------------------------------------------------------
local DAY_MATERIAL = Enum.Material.Glass
local NIGHT_MATERIAL = Enum.Material.Neon

local function bandFloor(part: BasePart): number
	return num(part:GetAttribute("Floor"), 0)
end

local function fxAlpha(pattern: number, floor: number, floors: number, t: number): number
	if pattern == 1 then
		return if (floor + math.floor(t * 4)) % 4 == 0 then 0 else 0.8
	elseif pattern == 2 then
		return 0.45 + 0.45 * math.sin(t * 3 + floor * 0.4)
	elseif pattern == 3 then
		return 0.45 + 0.45 * math.sin(t * 4)
	elseif pattern == 4 then
		return if (floor + math.floor(t * 2)) % 2 == 0 then 0 else 0.75
	elseif pattern == 5 then
		return if floor <= (t * 10) % (floors + 6) then 0 else 0.85
	elseif pattern == 6 then
		return if floor >= floors - (t * 10) % (floors + 6) then 0 else 0.85
	elseif pattern == 7 then
		local h = (floor * 73856093 + math.floor(t * 6) * 19349663) % 1000
		return if h > 480 then 0 else 0.8
	end
	return 0
end

local function stepLights(info: PlotInfo, t: number, cameraPos: Vector3)
	local bands = info.Bands
	if #bands == 0 then
		return
	end
	if night then
		local lit = math.floor((t - nightStart) / NIGHT_STEP)
		if lit > info.NightLit then
			for _, part in ipairs(bands) do
				local f = bandFloor(part)
				if f > info.NightLit and f <= lit and part.Parent then
					part.Material = NIGHT_MATERIAL
					part.Transparency = 0
				end
			end
			info.NightLit = lit
		end
		-- Neon-Fassaden-Kit: 8 Lichtmuster im Wechsel (nur nachts, nur in Sichtweite)
		if info.Fx and info.NightLit >= info.Floors and horizontal(cameraPos, info.Pivot.Position) < 900 then
			local pattern = math.floor(t / FX_PERIOD) % 8 + 1
			for _, part in ipairs(bands) do
				if part.Parent then
					part.Transparency = fxAlpha(pattern, bandFloor(part), info.Floors, t)
				end
			end
		end
	elseif info.NightLit ~= -1 then
		for _, part in ipairs(bands) do
			if part.Parent then
				part.Material = DAY_MATERIAL
				part.Transparency = 0.2
			end
		end
		info.NightLit = -1
	end
end

-- Alte Hülle (Morph/Abbau) ausblenden: von oben nach unten (Abbau) bzw. gleichmäßig (Morph)
local function stepFading(info: PlotInfo, t: number)
	for i = #info.Fading, 1, -1 do
		local entry = info.Fading[i]
		local model = entry.Model
		local alpha = math.clamp((t - entry.Start) / entry.Seconds, 0, 1)
		if model.Parent == nil or alpha >= 1 then
			table.remove(info.Fading, i)
		elseif t - entry.Last >= 0.05 then -- 20 Hz reichen für das Ausblenden
			entry.Last = t
			local teardown = info.Owner == 0
			local floorsVal = math.max(1, num(model:GetAttribute("Floors"), info.Floors))
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local fade = alpha
					if teardown then
						local f = num(d:GetAttribute("Floor"), floorsVal + 1)
						local order = 1 - (f / (floorsVal + 1))
						fade = math.clamp((alpha - order * 0.7) / 0.3, 0, 1)
					end
					d.LocalTransparencyModifier = fade
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) KRAN (Baustelle sichtbar für alle; Bau-Hilfe für Besucher, §B4.7)
-- ---------------------------------------------------------------------
local function destroyCrane(info: PlotInfo)
	-- Bau-Hilfe-Prompt VOR dem Zerstören des Masts abhängen (sonst wird er mit zerstört)
	if helpPrompt and helpPrompt.Parent and helpPrompt.Parent:GetAttribute("CranePlot") == info.Plot then
		placePrompt("Help", nil)
	end
	if info.Crane then
		for _, part in ipairs(info.Crane) do
			part:Destroy()
		end
	end
	info.Crane = nil
	info.CraneHook = nil
	info.CraneFloor = 0
end

local function buildCrane(info: PlotInfo, floor: number)
	destroyCrane(info)
	local folder = interiorFolder
	if not folder then
		return
	end
	local stage = TowerModels.StageOf(math.max(1, floor))
	local size = TowerModels.Footprint(stage, math.max(1, floor))
	local half = size / 2
	local roofY = math.max(0, floor - 1) * FH
	local base = info.Pivot * CFrame.new(half - 3, roofY, half - 3)
	local parts: { BasePart } = {}
	local function part(sz: Vector3, cf: CFrame, color: Color3, material: Enum.Material, neon: boolean?): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = not neon
		p.Size = sz
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p:SetAttribute("CranePlot", info.Plot)
		p.Parent = folder
		table.insert(parts, p)
		return p
	end
	local yellow = Color3.fromRGB(250, 204, 21)
	local dark = Color3.fromRGB(31, 41, 55)
	local mastH = 26
	local mast = part(Vector3.new(2, mastH, 2), base * CFrame.new(0, mastH / 2, 0), yellow, Enum.Material.DiamondPlate)
	part(Vector3.new(3, 2, 3), base * CFrame.new(0, mastH + 1, 0), dark, Enum.Material.Metal)
	part(
		Vector3.new(30, 1.2, 1.2),
		base * CFrame.new(-11, mastH + 2.6, -11) * CFrame.Angles(0, math.rad(45), 0),
		yellow,
		Enum.Material.DiamondPlate
	)
	part(
		Vector3.new(9, 1.2, 1.2),
		base * CFrame.new(4, mastH + 2.6, 4) * CFrame.Angles(0, math.rad(45), 0),
		yellow,
		Enum.Material.DiamondPlate
	)
	part(Vector3.new(3, 2.4, 3), base * CFrame.new(6, mastH + 1.6, 6), dark, Enum.Material.Concrete)
	part(
		Vector3.new(0.6, 0.6, 0.6),
		base * CFrame.new(0, mastH + 4.2, 0),
		Color3.fromRGB(239, 68, 68),
		Enum.Material.Neon,
		true
	)
	local hookTop = base * CFrame.new(-16, mastH + 2, -16)
	local hook = part(Vector3.new(1.4, 1.2, 1.4), hookTop * CFrame.new(0, -8, 0), dark, Enum.Material.Metal)
	part(Vector3.new(0.15, 8, 0.15), hookTop * CFrame.new(0, -4, 0), Color3.fromRGB(125, 136, 154), Enum.Material.Metal)
	-- Gerüst-Ring an der Baustelle (Etage floor)
	local ring = info.Pivot * CFrame.new(0, roofY + FH / 2, 0)
	local w = size + 3
	local orange = Color3.fromRGB(245, 158, 11)
	part(Vector3.new(w, 0.4, 0.4), ring * CFrame.new(0, 0, -w / 2), orange, Enum.Material.Neon, true)
	part(Vector3.new(w, 0.4, 0.4), ring * CFrame.new(0, 0, w / 2), orange, Enum.Material.Neon, true)
	part(Vector3.new(0.4, 0.4, w), ring * CFrame.new(-w / 2, 0, 0), orange, Enum.Material.Neon, true)
	part(Vector3.new(0.4, 0.4, w), ring * CFrame.new(w / 2, 0, 0), orange, Enum.Material.Neon, true)
	-- Hologramm mit Restzeit über dem Kran
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CraneInfo"
	billboard.Size = UDim2.fromOffset(220, 52)
	billboard.StudsOffset = Vector3.new(0, mastH / 2 + 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 400
	billboard.LightInfluence = 0
	local panel = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.15,
		Parent = billboard,
	}, { UI.Corner(12), UI.Create("UIStroke", { Color = Theme.Warn, Thickness = 1, Transparency = 0.3 }) })
	UI.Label({
		Name = "Text",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Face = "MonoBold",
		TextColor3 = Theme.Text,
		MaxText = 22,
		Parent = panel,
	})
	billboard.Parent = mast
	info.Crane = parts
	info.CraneHook = hook
	info.CraneFloor = floor
	mast:SetAttribute("CraneMast", true)
end

local function stepCrane(info: PlotInfo, now: number, cameraPos: Vector3)
	local floor = math.floor(num(info.Folder:GetAttribute("BuildFloor"), 0))
	local untilUnix = num(info.Folder:GetAttribute("BuildUntil"), 0)
	local local_ = info.CraneUntil > now and info.CraneFloor > 0
	local wanted = if floor > 0 then floor elseif local_ then info.CraneFloor else 0
	local inRange = horizontal(cameraPos, info.Pivot.Position) < 700
	if wanted <= 0 or not inRange or info.Owner == 0 then
		if info.Crane then
			destroyCrane(info)
		end
		return
	end
	if not info.Crane or info.CraneFloor ~= wanted then
		buildCrane(info, wanted)
	end
	local crane = info.Crane
	local mast = crane and crane[1]
	local billboard = mast and mast:FindFirstChild("CraneInfo")
	local label = billboard and billboard:FindFirstChild("Text", true) :: TextLabel?
	if label then
		local remaining = math.max(0, untilUnix - now)
		local okFmt, text = pcall(ctx.Format.Duration, remaining, lang())
		label.Text = T("tui.crane", wanted, if okFmt then text else tostring(math.floor(remaining)))
	end
	-- Bau-Hilfe für Besucher (nicht der Besitzer)
	if mast and floor > 0 and info.Owner ~= player.UserId and info.Plot == active then
		local hp = placePrompt("Help", mast)
		if hp and hp:GetAttribute("Owner") ~= info.Owner then
			hp:SetAttribute("Owner", info.Owner)
		end
	end
end

-- ---------------------------------------------------------------------
-- 8) INTERAKTION: Kassen-Tor, Aufzug, Respekt, Bau-Hilfe
-- ---------------------------------------------------------------------
local function stepGate(info: PlotInfo, now: number)
	if info.Owner ~= player.UserId then
		return
	end
	local part = rootPart()
	if not part or now - gateAt < GATE_GAP then
		return
	end
	local tower = ctx.State.Tower
	local vault = if type(tower) == "table" then num(tower.Vault, 0) else 0
	if vault <= 0 then
		return
	end
	local half = TowerModels.Footprint(info.Stage, 1) / 2
	local localPos = info.Pivot:PointToObjectSpace(part.Position)
	local gateZ = -half - 10
	if math.abs(localPos.X) <= 4.6 and math.abs(localPos.Z - gateZ) <= 1.8 and localPos.Y < 11 then
		gateAt = now
		task.spawn(function()
			ctx.RequestFull("TowerCollect", {}, true)
		end)
	end
end

local function stepVaultGlow(info: PlotInfo, t: number)
	local ring = info.VaultRing
	if not ring or ring.Parent == nil then
		return
	end
	local full = false
	if info.Owner == player.UserId then
		local tower = ctx.State.Tower
		if type(tower) == "table" then
			local cap = num(tower.VaultCap, 0)
			full = cap > 0 and num(tower.Vault, 0) >= cap
		end
	end
	if full then
		ring.Color = Theme.Down
		ring.Transparency = 0.3 + 0.3 * math.sin(t * 5)
	elseif ring.Color ~= Theme.Gold or ring.Transparency ~= 0 then
		ring.Color = Theme.Gold
		ring.Transparency = 0
	end
end

local function setupPrompts()
	placePrompt("Elevator", nil)
	placePrompt("Respekt", nil)
	placePrompt("Help", nil)
	ProximityPromptService.PromptTriggered:Connect(function(p: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		if p == prompt then
			local plot = TowerView.InsideTower() or active
			if plot then
				call("Elevator", "OpenPanel", plot)
			end
		elseif p == respektPrompt then
			local info = if active then plots[active] else nil
			if info and info.Owner > 0 and info.Owner ~= player.UserId then
				task.spawn(function()
					ctx.RequestFull("SocialRespekt", { UserId = info.Owner })
				end)
			end
		elseif p == helpPrompt then
			local owner = p:GetAttribute("Owner")
			if type(owner) == "number" and owner > 0 then
				task.spawn(function()
					ctx.RequestFull("TowerHelp", { OwnerUserId = owner })
				end)
			end
		end
	end)
end

local function refreshPromptTexts()
	if prompt then
		prompt.ActionText = T("tui.elevator.prompt")
	end
	if respektPrompt then
		respektPrompt.ActionText = T("tui.respekt.prompt")
	end
	if helpPrompt then
		helpPrompt.ActionText = T("tui.help.prompt")
	end
end

-- ---------------------------------------------------------------------
-- 9) AKTIVER TOWER (Hooks Plot:Enter/Plot:Leave)
-- ---------------------------------------------------------------------
local function pickActive(pos: Vector3): number?
	local best: number? = nil
	local bestDist = math.huge
	for plot, info in pairs(plots) do
		if info.Owner > 0 then
			local d = horizontal(pos, info.Pivot.Position)
			if d <= ACTIVE_RANGE and d < bestDist then
				best, bestDist = plot, d
			end
		end
	end
	return best
end

local function setActive(plot: number?)
	local owner = if plot and plots[plot] then plots[plot].Owner else 0
	if plot == active and owner == activeOwner then
		return
	end
	if active then
		ctx.Hooks.Fire("Plot:Leave", active, activeOwner)
	end
	active = plot
	activeOwner = owner
	if plot then
		ctx.Hooks.Fire("Plot:Enter", plot, owner)
	end
	-- Respekt-Knopf nur an fremden Säulen
	local info = if plot then plots[plot] else nil
	local target = if info and info.Owner > 0 and info.Owner ~= player.UserId then info.Respekt else nil
	placePrompt("Respekt", target)
end

-- ---------------------------------------------------------------------
-- 10) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function TowerView.InsideTower(): number?
	local part = rootPart()
	if not part then
		return nil
	end
	for plot, info in pairs(plots) do
		if info.Owner > 0 and info.Floors > 0 then
			local localPos = info.Pivot:PointToObjectSpace(part.Position)
			local floor = math.clamp(math.floor((localPos.Y - 0.5) / FH) + 1, 1, info.Floors)
			local half = TowerModels.Footprint(info.Stage, floor) / 2 + 1
			if
				math.abs(localPos.X) <= half
				and math.abs(localPos.Z) <= half
				and localPos.Y > -2
				and localPos.Y < info.Floors * FH + 3
			then
				return plot
			end
		end
	end
	return nil
end

function TowerView.ActivePlot(): number?
	return active
end

function TowerView.OwnPlot(): number?
	return ownPlot()
end

function TowerView.PlotFolder(plot: number): Folder?
	local info = plots[plot]
	return if info then info.Folder else nil
end

function TowerView.TowerModel(plot: number): Model?
	local info = plots[plot]
	local model = info and info.Model
	return if model and model.Parent then model else nil
end

function TowerView.PlotInfo(plot: number): { [string]: any }?
	local info = plots[plot]
	if not info then
		return nil
	end
	local name = info.Folder:GetAttribute("Name")
	return {
		Pivot = info.Pivot,
		Stage = info.Stage,
		Floors = info.Floors,
		Owner = info.Owner,
		OwnerName = info.Folder:GetAttribute("OwnerName"),
		Name = if type(name) == "string" then name else "1:1",
		TowerName = if info.Owner > 0 then towerNameText(info) else "",
		Layout = info.Layout,
		Skin = info.Folder:GetAttribute("Skin"),
		Neon = info.Folder:GetAttribute("Neon"),
		Crown = info.Folder:GetAttribute("Crown"),
	}
end

function TowerView.Plots(): { number }
	local list: { number } = {}
	for plot in pairs(plots) do
		table.insert(list, plot)
	end
	table.sort(list)
	return list
end

function TowerView.FloorOf(position: Vector3, plot: number): number
	local info = plots[plot]
	if not info then
		return 1
	end
	local localPos = info.Pivot:PointToObjectSpace(position)
	return math.clamp(math.floor((localPos.Y - 0.5) / FH) + 1, 1, math.max(1, info.Floors))
end

function TowerView.CurrentFloor(): number?
	local plot = TowerView.InsideTower()
	local part = rootPart()
	if not plot or not part then
		return nil
	end
	return TowerView.FloorOf(part.Position, plot)
end

function TowerView.FloorCFrame(plot: number, floor: number): CFrame?
	local info = plots[plot]
	if not info then
		return nil
	end
	return floorCFrame(info, math.clamp(math.floor(floor), 1, math.max(1, info.Floors)))
end

function TowerView.TopCFrame(plot: number): CFrame?
	local info = plots[plot]
	if not info then
		return nil
	end
	return info.Pivot * CFrame.new(0, info.Floors * FH, 0)
end

-- Aufzugstüren einer gebauten Etage des aktiven Towers öffnen (0 = zu, 1 = offen); false = Etage nicht gebaut
function TowerView.SetDoors(plot: number, floor: number, openness: number): boolean
	if plot ~= builtPlot then
		return false
	end
	local build = built[floor]
	local doors = build and build.Doors
	if not doors then
		return false
	end
	local slide = math.clamp(num(openness, 0), 0, 1) * 2.25
	for _, door in ipairs(doors) do
		if door.Part.Parent then
			door.Part.CFrame = door.Base * CFrame.new(door.Side * slide, 0, 0)
		end
	end
	return true
end

-- eingeschaltete Interior-Lichter (für das gemeinsame Licht-Budget in WorldLook)
function TowerView.InteriorLights(): number
	return interiorLightsOn
end

function TowerView.NeonBands(plot: number): { BasePart }
	local info = plots[plot]
	return if info then table.clone(info.Bands) else {}
end

-- Kran sofort zeigen (Effekt "Crane" kommt vor dem Attribut); seconds = Szenen-/Bauzeit
function TowerView.ShowCrane(plot: number, floor: number, seconds: number)
	local info = plots[plot]
	if not info then
		return
	end
	info.CraneFloor = math.max(1, math.floor(num(floor, 1)))
	info.CraneUntil = workspace:GetServerTimeNow() + math.clamp(num(seconds, 3), 1, 6) + 1
	local pos = focusPosition()
	if pos then
		stepCrane(info, workspace:GetServerTimeNow(), pos)
	end
end

function TowerView.CraneHook(plot: number): BasePart?
	local info = plots[plot]
	return if info then info.CraneHook else nil
end

-- ---------------------------------------------------------------------
-- 11) FRAME (ein PreRender-Loop) & LEBENSZYKLUS
-- ---------------------------------------------------------------------
function TowerView.Frame(dt: number)
	clock += dt
	local t = os.clock()
	local now = workspace:GetServerTimeNow()
	local pos = focusPosition()
	local camera = workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else (pos or Vector3.zero)
	-- Tag/Nacht: dieselbe Schaltung wie die Stadt-Fenster (WorldLook: Schwellen aus Config.City.Look + Overrides
	-- wie "Night"/"Golden" in Kamerafahrten); ohne WorldLook die Server-Uhr
	local okNight, isNight = call("WorldLook", "IsNight")
	if not okNight then
		okNight, isNight = pcall(ctx.Clock.IsNight, ctx.Clock.Tick())
	end
	local nowNight = okNight and isNight == true
	if nowNight ~= night then
		night = nowNight
		nightStart = t
		for _, info in pairs(plots) do
			info.NightLit = 0 -- Nacht: Kaskade von unten; Tag: einmal zurück auf Glas
		end
	end
	if pos then
		setActive(pickActive(pos))
	end
	if signLang ~= lang() then
		signLang = lang()
		refreshPromptTexts()
		for _, info in pairs(plots) do
			refreshSign(info)
		end
	end
	-- Interiors des aktiven Towers
	processInteriors(if active then plots[active] else nil)
	-- Animationen: Interior-Gruppen nah an der Kamera + Kronen sichtbarer Tower
	table.clear(animParts)
	table.clear(animCFrames)
	if pos and active then
		local info = plots[active]
		local current = if info then currentFloor(info) else 1
		for floor, build in pairs(built) do
			if math.abs(floor - current) <= 1 then
				for _, group in ipairs(build.Groups) do
					if (group.Center - cameraPos).Magnitude <= ANIM_RANGE then
						stepGroup(group, t)
					end
				end
			end
		end
	end
	local refreshLed = t - ledAt >= LED_GAP
	if refreshLed then
		ledAt = t
	end
	for _, info in pairs(plots) do
		if info.ScanDirty then
			scanModel(info)
		end
		local distance = horizontal(cameraPos, info.Pivot.Position)
		if info.Model and distance < CROWN_RANGE then
			for _, group in ipairs(info.Anim) do
				stepGroup(group, t)
			end
		end
		if info.Model then
			stepLights(info, t, cameraPos)
			if refreshLed and distance < 700 then
				refreshLeds(info)
			end
			stepVaultGlow(info, t)
		end
		if #info.Fading > 0 then
			stepFading(info, t)
		end
		if pos then
			stepCrane(info, now, cameraPos)
		end
	end
	if #animParts > 0 then
		workspace:BulkMoveTo(animParts, animCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if active and plots[active] then
		stepGate(plots[active], now)
	end
	-- Schritte der anderen WP8-Module (kein zweiter Render-Loop)
	call("EffectsTower", "Step", dt)
	call("Elevator", "Step", dt)
	call("Boutique", "Step", dt)
	uiTick += dt
	if uiTick >= 1 then
		uiTick = 0
		call("TowerUI", "Tick")
		call("WelcomeBack", "Tick")
	end
end

function TowerView.Init(context: any)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "AkyInteriors" -- nur lokal (Client), wird nicht repliziert
	folder.Parent = workspace
	interiorFolder = folder
	lightBudget = budget("Lights", 16)
	ctx.Hooks.On("Quality", function()
		lightBudget = budget("Lights", 16)
	end)
	setupPrompts()
end

function TowerView.Start()
	watchRoot()
end

return TowerView
