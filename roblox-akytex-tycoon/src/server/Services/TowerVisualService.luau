-- =====================================================================
--  AKYTEX TYCOON – Tower-Hüllen & Plot-Attribute (Server/Services/TowerVisualService)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C5.7, §B3 (Server baut nur die Hülle:
--  ≤ 8 Parts je Etage, Krone ≤ 60, Plot-Ausstattung ≤ 40, 10 Tower × 50 Etagen ≤ 4.600 Parts, Aufbau über eine
--  Scheduler-Warteschlange ≤ 6 Etagen je Frame; Streaming: Hülle PersistentPerPlayer für den Besitzer, Atomic für
--  alle anderen, LevelOfDetail = StreamingMesh), §B4.2/§B4.9 (Silhouetten, Fassaden, Neon, Kronen), §C10 + §C12.3
--  (Plot-Attribute, "Layout" ≤ 2 KB).
--
--  Welt-Struktur (Ordner sind immer repliziert, auch mit StreamingEnabled):
--    Workspace.AkyTowers.Plot<n>   (Folder)  Attribute: Owner (UserId, 0 = frei), OwnerName, Stage, Floors, Layout,
--                                            Skin, Neon, Crown, Name ("a:n"), Lobby ("J"/"W"/"JW"), Pivot (CFrame),
--                                            BuildFloor, BuildStart, BuildUntil (Unix), Fx (Neon-Fassaden-Kit)
--      Tower (Model)                          Hülle: Floors/F<n>, Spine, Crown, Site (Parts aus Shared/TowerModels)
--      TowerOld (Model, kurzzeitig)           alte Hülle beim Stufen-Morph (2,5 s, Client blendet sie aus) bzw. beim
--                                             Abbau nach dem Verlassen (1,6 s, Client spielt den Kran-Abbau)
--  Interiors baut NUR der Client (TowerView) aus "Layout".
--
--  Öffentliche API (§C5.7):
--    TowerVisualService.Rebuild(p)              Hülle + Plot-Attribute aus Data.Tower (Scheduler-Warteschlange)
--    TowerVisualService.FloorAdded(p, floor)    neue Etage anhängen (bei Stufenwechsel: Morph = Neuaufbau)
--    TowerVisualService.Clear(plot)             Hülle abbauen (Kran-Abbau beim Client), Attribute zurücksetzen
--    TowerVisualService.Touch(p)                Layout-Attribut neu schreiben (Raum/Stufe/Personal/Deko/Privat/Name)
--  Ergänzungen: TowerVisualService.PartCount(): number · TowerVisualService.PlotFolder(plot): Folder?
--    TowerVisualService._Test = { Encode, Decode, Count, Layout(tower) }   (reine Helfer für VisualTests)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local TowerModels = require(Shared:WaitForChild("TowerModels"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local TowerVisualService = {}
local Services: any = nil

local PREFIX = "[TowerVisualService] "
local FOLDER_NAME = "AkyTowers"
local FLOORS_PER_FRAME = 6 -- §B3/§C16: Hüllen-Bau ≤ 6 Etagen je Frame (über alle Tower zusammen)
local MORPH_SECONDS = 2.5 -- Stufen-Morph: alte Hülle bleibt so lange (Client blendet aus)
local TEARDOWN_SECONDS = 1.6 -- Abbau nach dem Verlassen (Client: Kran-Abbau 1,5 s)
local LAYOUT_MAX = 2048
local FX_REFRESH = 10 -- Sekunden: Neon-Fassaden-Kit-Besitz neu prüfen
local ERROR_LOG_EVERY = 10

local TCFG: { [string]: any } = if type(Config.Tower) == "table" then Config.Tower else {}

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local FLOOR_HEIGHT = num(TCFG.FloorHeight, 12)
local MAX_FLOORS = math.clamp(math.floor(num(TCFG.Floors, 50)), 1, 50)
local PLOTS = math.clamp(math.floor(num(type(Config.Server) == "table" and Config.Server.Plots or nil, 10)), 1, 32)
local DEFAULT_SKIN = if type(TCFG.DefaultSkin) == "string" then TCFG.DefaultSkin else "GlassBlue"
local DEFAULT_NEON = if type(TCFG.DefaultNeon) == "string" then TCFG.DefaultNeon else "Accent"
local SIGNS: { [string]: any } = if type(Config.Decor) == "table" and type(Config.Decor.Signs) == "table"
	then Config.Decor.Signs
	else {}

type Job = {
	Token: number,
	Model: Model,
	Origin: CFrame,
	Stage: number,
	Floors: number,
	Skin: string,
	Neon: string,
	Crown: string,
	Next: number,
	Morph: boolean,
}

type PlotState = {
	Plot: number,
	Folder: Folder,
	Owner: Player?,
	Model: Model?,
	Token: number,
	Stage: number,
	Floors: number,
	Skin: string,
	Neon: string,
	Crown: string,
	Job: Job?,
	FxAt: number,
}

-- ---------------------------------------------------------------------
-- 1) ZUSTAND
-- ---------------------------------------------------------------------
local root: Folder? = nil
local plots: { [number]: PlotState } = {}
local plotOfPlayer: { [Player]: number } = {} -- bei PlayerRemoving geleert
local queue: { number } = {} -- Plots mit wartendem Hüllen-Auftrag (Reihenfolge)
local errorLogAt: { [string]: number } = {}

local function logError(where: string, err: any)
	local t = os.clock()
	if t - (errorLogAt[where] or -math.huge) >= ERROR_LOG_EVERY then
		errorLogAt[where] = t
		warn(PREFIX .. where .. ": " .. tostring(err))
	end
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[serviceName]
	local fn = if type(s) == "table" then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(serviceName .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" and type(data.Tower) == "table" then
		return data
	end
	return nil
end

local function plotCFrame(plot: number): CFrame
	local ok, cf = call("PlotService", "PlotCFrame", plot)
	if ok and typeof(cf) == "CFrame" and Util.IsFiniteVector(cf.Position) then
		return cf
	end
	-- Ersatz: Ring-Formel §A5 (R 420, 18° + k · 36°, Blick zur Plaza)
	local ring = if type(TCFG.Plots) == "table" then TCFG.Plots else {}
	local angle = math.rad(num(ring.StartAngle, 18) + (plot - 1) * num(ring.Step, 36))
	local r = num(ring.Radius, 420)
	local position = Vector3.new(r * math.cos(angle), 0, r * math.sin(angle))
	return CFrame.lookAt(position, Vector3.zero)
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

-- ---------------------------------------------------------------------
-- 2) WELT-ORDNER
-- ---------------------------------------------------------------------
local function ensureRoot(): Folder
	local existing = root
	if existing and existing.Parent == workspace then
		return existing
	end
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy() -- Reste eines früheren Laufs (Studio-Neustart der Services)
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	root = folder
	return folder
end

local function resetAttributes(folder: Folder)
	setAttr(folder, "Owner", 0)
	setAttr(folder, "OwnerName", "")
	setAttr(folder, "Stage", 1)
	setAttr(folder, "Floors", 0)
	setAttr(folder, "Layout", "")
	setAttr(folder, "Skin", DEFAULT_SKIN)
	setAttr(folder, "Neon", DEFAULT_NEON)
	setAttr(folder, "Crown", "")
	setAttr(folder, "Name", "1:1")
	setAttr(folder, "Lobby", "")
	setAttr(folder, "BuildFloor", 0)
	setAttr(folder, "BuildStart", 0)
	setAttr(folder, "BuildUntil", 0)
	setAttr(folder, "Fx", false)
end

local function stateOf(plot: number): PlotState?
	if not Util.IsFinite(plot) or plot % 1 ~= 0 or plot < 1 or plot > PLOTS then
		return nil
	end
	local state = plots[plot]
	if state and state.Folder.Parent ~= nil then
		return state
	end
	local parent = ensureRoot()
	local folder = parent:FindFirstChild("Plot" .. plot)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = "Plot" .. plot
		folder.Parent = parent
	end
	local f = folder :: Folder
	resetAttributes(f)
	f:SetAttribute("Plot", plot)
	f:SetAttribute("Pivot", plotCFrame(plot))
	local created: PlotState = {
		Plot = plot,
		Folder = f,
		Owner = nil,
		Model = nil,
		Token = 0,
		Stage = 1,
		Floors = 0,
		Skin = DEFAULT_SKIN,
		Neon = DEFAULT_NEON,
		Crown = "",
		Job = nil,
		FxAt = 0,
	}
	plots[plot] = created
	return created
end

-- ---------------------------------------------------------------------
-- 3) TEILE BAUEN
-- ---------------------------------------------------------------------
-- Neon-Schriftzug (Marke/„STARTUP“) als Server-SurfaceGui – sprachneutral, Text aus Config.Decor.Signs
local function decorateSign(part: BasePart, neonColor: Color3)
	local key = part:GetAttribute("Sign")
	local text = if type(key) == "string" then SIGNS[key] else nil
	if type(text) ~= "string" or text == "" then
		return
	end
	local face = part:GetAttribute("Face")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = if face == "Back" then Enum.NormalId.Back else Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 900
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
	label.TextColor3 = neonColor
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = neonColor
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
end

local function hexColor(hex: string): Color3
	local r, g, b = TowerModels.Hex(hex)
	return Color3.fromRGB(r, g, b)
end

local function buildList(specs: { any }, origin: CFrame, parent: Instance, neon: string): number
	local neonColor = hexColor(TowerModels.NeonHex(neon))
	for _, spec in ipairs(specs) do
		local part = TowerModels.Instantiate(spec, origin, nil)
		if part:GetAttribute("Sign") ~= nil then
			decorateSign(part, neonColor)
		end
		part.Parent = parent
	end
	return #specs
end

local function folderIn(model: Instance, name: string): Folder
	local existing = model:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = model
	return folder
end

local function buildFloor(job: Job, floor: number)
	local floors = folderIn(job.Model, "Floors")
	local old = floors:FindFirstChild("F" .. floor)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "F" .. floor
	folder:SetAttribute("Floor", floor)
	buildList(TowerModels.Shell(job.Stage, floor, job.Skin, job.Neon), job.Origin, folder, job.Neon)
	folder.Parent = floors
end

-- Senkrechte Teile, Krone und Plot-Ausstattung hängen von der Etagenzahl ab -> komplett neu
local function buildTop(job: Job)
	for _, name in ipairs({ "Spine", "Crown", "Site" }) do
		local old = job.Model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local spine = Instance.new("Folder")
	spine.Name = "Spine"
	buildList(TowerModels.Spine(job.Stage, job.Floors, job.Skin, job.Neon), job.Origin, spine, job.Neon)
	spine.Parent = job.Model
	if job.Floors > 0 then
		local crown = Instance.new("Folder")
		crown.Name = "Crown"
		local top = job.Origin * CFrame.new(0, job.Floors * FLOOR_HEIGHT, 0)
		buildList(TowerModels.Crown(job.Stage, job.Crown, job.Floors, job.Skin, job.Neon), top, crown, job.Neon)
		crown.Parent = job.Model
	end
	local site = Instance.new("Folder")
	site.Name = "Site"
	buildList(TowerModels.Site(job.Stage, job.Floors, job.Skin, job.Neon), job.Origin, site, job.Neon)
	site.Parent = job.Model
end

local function newModel(plot: number, origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Tower"
	model:SetAttribute("Plot", plot)
	model.WorldPivot = origin
	-- §B3: Skyline bleibt aus der Ferne sichtbar; eigener Plot dauerhaft geladen (AddPersistentPlayer beim Einhängen)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	pcall(function()
		model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	end)
	return model
end

local function scheduleDestroy(model: Model, seconds: number)
	model.Name = "TowerOld"
	model:SetAttribute("Fading", true)
	model:SetAttribute("FadeSeconds", seconds)
	task.delay(seconds, function()
		if model.Parent ~= nil then
			model:Destroy()
		end
	end)
end

local function addPersistent(model: Model, owner: Player?)
	if owner and owner.Parent == Players then
		pcall(function()
			model:AddPersistentPlayer(owner)
		end)
	end
end

-- Auftrag fertig: neue Hülle einhängen, alte (Morph) kurz stehen lassen
local function finishJob(state: PlotState, job: Job)
	buildTop(job)
	local old = state.Model
	job.Model:SetAttribute("Stage", job.Stage)
	job.Model:SetAttribute("Floors", job.Floors)
	job.Model.Parent = state.Folder
	addPersistent(job.Model, state.Owner)
	if old and old ~= job.Model then
		if job.Morph then
			scheduleDestroy(old, MORPH_SECONDS)
		else
			old:Destroy()
		end
	end
	state.Model = job.Model
	state.Stage = job.Stage
	state.Floors = job.Floors
	state.Skin = job.Skin
	state.Neon = job.Neon
	state.Crown = job.Crown
	state.Job = nil
end

-- Warteschlange: höchstens FLOORS_PER_FRAME Etagen je Frame über alle Tower
local function shellJob(_dt: number)
	local budget = FLOORS_PER_FRAME
	local guard = 0
	while budget > 0 and #queue > 0 and guard < PLOTS * 2 do
		guard += 1
		local plot = queue[1]
		local state = plots[plot]
		local job = state and state.Job
		if not state or not job or job.Token ~= state.Token then
			table.remove(queue, 1)
			continue
		end
		while budget > 0 and job.Next <= job.Floors do
			local ok, err = pcall(buildFloor, job, job.Next)
			if not ok then
				logError("buildFloor", err)
			end
			job.Next += 1
			budget -= 1
		end
		if job.Next > job.Floors then
			local ok, err = pcall(finishJob, state, job)
			if not ok then
				logError("finishJob", err)
				state.Job = nil
			end
			table.remove(queue, 1)
		end
	end
end

local function enqueue(plot: number)
	if not table.find(queue, plot) then
		table.insert(queue, plot)
	end
end

-- ---------------------------------------------------------------------
-- 4) ATTRIBUTE AUS DEN DATEN
-- ---------------------------------------------------------------------
local function towerInfo(data: { [string]: any }): (number, number, string, string, string)
	local tower = data.Tower
	local floors = if type(tower.Floors) == "table" then math.min(#tower.Floors, MAX_FLOORS) else 0
	local stage = TowerModels.StageOf(floors)
	local skin = if type(tower.Skin) == "string" then tower.Skin else DEFAULT_SKIN
	local neon = if type(tower.Neon) == "string" then tower.Neon else DEFAULT_NEON
	local crown = if type(tower.Crown) == "string" then tower.Crown else ""
	return floors, stage, skin, neon, crown
end

-- Layout ≤ 2 KB: notfalls die Deko der obersten Etagen weglassen (Raum/Stufe/Personal bleiben vollständig)
local function layoutOf(tower: { [string]: any }): string
	local floors = if type(tower.Floors) == "table" then tower.Floors else {}
	local private = if type(tower.Private) == "table" then tower.Private else {}
	local text = TowerModels.EncodeLayout(floors, private)
	if #text <= LAYOUT_MAX then
		return text
	end
	local trimmed: { any } = {}
	for i, floor in ipairs(floors) do
		trimmed[i] = { R = floor.R, L = floor.L, S = floor.S, D = floor.D }
	end
	for i = #trimmed, 1, -1 do
		trimmed[i].D = {}
		text = TowerModels.EncodeLayout(trimmed, private)
		if #text <= LAYOUT_MAX then
			break
		end
	end
	return string.sub(text, 1, LAYOUT_MAX)
end

local function writeAttributes(state: PlotState, p: Player, data: { [string]: any })
	local folder = state.Folder
	local tower = data.Tower
	local floors, stage, skin, neon, crown = towerInfo(data)
	setAttr(folder, "Owner", p.UserId)
	setAttr(folder, "OwnerName", p.DisplayName)
	setAttr(folder, "Stage", stage)
	setAttr(folder, "Floors", floors)
	setAttr(folder, "Skin", skin)
	setAttr(folder, "Neon", neon)
	setAttr(folder, "Crown", crown)
	local name = if type(tower.Name) == "table" then tower.Name else {}
	setAttr(folder, "Name", string.format("%d:%d", math.floor(num(name.A, 1)), math.floor(num(name.N, 1))))
	setAttr(
		folder,
		"Lobby",
		(if tower.Janitor == true then "J" else "") .. (if tower.Security == true then "W" else "")
	)
	setAttr(folder, "Layout", layoutOf(tower))
	setAttr(folder, "Pivot", plotCFrame(state.Plot))
end

local function writeBuild(state: PlotState, data: { [string]: any })
	local build = data.Tower.Build
	local floor = if type(build) == "table" then build.Floor else nil
	local folder = state.Folder
	if Util.IsFinite(floor) then
		setAttr(folder, "BuildFloor", math.floor(floor))
		setAttr(folder, "BuildStart", math.floor(num(build.Start, 0)))
		setAttr(folder, "BuildUntil", math.floor(num(build.Until, 0)))
	else
		setAttr(folder, "BuildFloor", 0)
		setAttr(folder, "BuildStart", 0)
		setAttr(folder, "BuildUntil", 0)
	end
end

local function refreshFx(state: PlotState, p: Player, force: boolean)
	local t = os.clock()
	if not force and t - state.FxAt < FX_REFRESH then
		return
	end
	state.FxAt = t
	local ok, has = call("MonetizationService", "HasPass", p, "FacadeKit")
	setAttr(state.Folder, "Fx", ok and has == true)
end

local function plotForPlayer(p: Player): number?
	local ok, plot = call("PlotService", "PlotOf", p)
	if ok and Util.IsFinite(plot) then
		return plot
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 5) ÖFFENTLICHE API (§C5.7)
-- ---------------------------------------------------------------------
function TowerVisualService.Rebuild(p: Player)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return
	end
	local plot = plotForPlayer(p)
	local data = dataOf(p)
	if not plot or not data then
		return
	end
	local state = stateOf(plot)
	if not state then
		return
	end
	-- anderer Besitzer im selben Plot (Wechsel): alte Hülle sofort weg
	if state.Owner ~= p and state.Model then
		state.Model:Destroy()
		state.Model = nil
		state.Floors = 0
	end
	state.Owner = p
	plotOfPlayer[p] = plot
	writeAttributes(state, p, data)
	writeBuild(state, data)
	refreshFx(state, p, true)
	local floors, stage, skin, neon, crown = towerInfo(data)
	state.Token += 1
	local origin = plotCFrame(plot)
	local job: Job = {
		Token = state.Token,
		Model = newModel(plot, origin),
		Origin = origin,
		Stage = stage,
		Floors = floors,
		Skin = skin,
		Neon = neon,
		Crown = crown,
		Next = 1,
		Morph = state.Model ~= nil and stage ~= state.Stage,
	}
	if state.Job then
		state.Job.Model:Destroy() -- halb gebauter, veralteter Auftrag
	end
	state.Job = job
	enqueue(plot)
end

function TowerVisualService.FloorAdded(p: Player, floor: number)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return
	end
	local plot = plotForPlayer(p)
	local data = dataOf(p)
	local state = if plot then stateOf(plot) else nil
	if not plot or not data or not state then
		return
	end
	local floors, stage, skin, neon, crown = towerInfo(data)
	local model = state.Model
	local incremental = model ~= nil
		and model.Parent == state.Folder
		and state.Job == nil
		and state.Owner == p
		and stage == state.Stage
		and floors == state.Floors + 1
		and floor == floors
		and skin == state.Skin
		and neon == state.Neon
		and crown == state.Crown
		and floors > 1
	if not incremental or not model then
		TowerVisualService.Rebuild(p)
		return
	end
	-- gleiche Stufe: nur die neue Etage + Spine/Krone/Site neu (≤ 8 + 13 + 60 + 40 Parts)
	local job: Job = {
		Token = state.Token,
		Model = model,
		Origin = plotCFrame(plot),
		Stage = stage,
		Floors = floors,
		Skin = skin,
		Neon = neon,
		Crown = crown,
		Next = floor,
		Morph = false,
	}
	local ok, err = pcall(function()
		buildFloor(job, floor)
		buildTop(job)
	end)
	if not ok then
		logError("FloorAdded", err)
		TowerVisualService.Rebuild(p)
		return
	end
	state.Floors = floors
	model:SetAttribute("Floors", floors)
	writeAttributes(state, p, data)
	writeBuild(state, data)
end

function TowerVisualService.Clear(plot: number)
	local state = stateOf(plot)
	if not state then
		return
	end
	state.Token += 1
	if state.Job then
		state.Job.Model:Destroy()
		state.Job = nil
	end
	local owner = state.Owner
	if owner then
		plotOfPlayer[owner] = nil
	end
	state.Owner = nil
	state.Floors = 0
	state.Stage = 1
	resetAttributes(state.Folder)
	local model = state.Model
	state.Model = nil
	if model then
		scheduleDestroy(model, TEARDOWN_SECONDS)
	end
end

function TowerVisualService.Touch(p: Player)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return
	end
	local plot = plotOfPlayer[p] or plotForPlayer(p)
	local data = dataOf(p)
	local state = if plot then stateOf(plot) else nil
	if not state or not data then
		return
	end
	if state.Owner ~= p then
		TowerVisualService.Rebuild(p)
		return
	end
	writeAttributes(state, p, data)
end

function TowerVisualService.PlotFolder(plot: number): Folder?
	local state = stateOf(plot)
	return if state then state.Folder else nil
end

-- Server-Teile aller Hüllen (SelfTest / Admin-Statistik)
function TowerVisualService.PartCount(): number
	local count = 0
	local folder = root
	if not folder then
		return 0
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

TowerVisualService._Test = {
	Encode = TowerModels.EncodeLayout,
	Decode = TowerModels.DecodeLayout,
	Count = TowerModels.Count,
	Layout = layoutOf,
}

-- ---------------------------------------------------------------------
-- 6) TAKTE & LEBENSZYKLUS
-- ---------------------------------------------------------------------
-- 1 Hz: Baustellen-Attribute (Kran, Bau-Hilfe) + Neon-Fassaden-Kit aller Besitzer
local function siteJob(_dt: number)
	for _, state in pairs(plots) do
		local owner = state.Owner
		if owner and owner.Parent == Players then
			local data = dataOf(owner)
			if data then
				writeBuild(state, data)
				refreshFx(state, owner, false)
			end
		end
	end
end

local function onPlayerRemoving(p: Player)
	local plot = plotOfPlayer[p]
	plotOfPlayer[p] = nil
	-- PlotService ruft Clear(plot); falls nicht (Dienst fehlt), räumen wir selbst auf
	if plot then
		local state = plots[plot]
		if state and state.Owner == p then
			task.defer(function()
				local current = plots[plot]
				if current and current.Owner == p then
					TowerVisualService.Clear(plot)
				end
			end)
		end
	end
end

function TowerVisualService.Init(services: any)
	Services = services
	ensureRoot()
	for plot = 1, PLOTS do
		stateOf(plot)
	end
end

function TowerVisualService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.EveryFrame("TowerShells", shellJob)
	Scheduler.Every("TowerBuildSites", 1, siteJob)
	-- Pivot nachziehen, sobald CityService die Plot-Seiten kennt (Start-Reihenfolge)
	task.defer(function()
		for plot = 1, PLOTS do
			local state = plots[plot]
			if state then
				setAttr(state.Folder, "Pivot", plotCFrame(plot))
			end
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.defer(TowerVisualService.Rebuild, p)
	end
end

return TowerVisualService
