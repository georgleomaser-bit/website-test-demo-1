-- =====================================================================
--  AKYTEX TYCOON – Eingabe-Belegung über ContextActionService (Client/Modules/Controls)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5. Basis: CC-Controls (CAS-Motor, REUSE §3.18).
--
--  Alle Tasten/Knöpfe aus Config.Client.Keys (PC) und Config.Client.Gamepad laufen über
--  ContextActionService:BindActionAtPriority (createTouchButton = false). Eigene Touch-Knöpfe
--  (Modul TouchControls) speisen dieselben Aktionen über Controls.Emit ein. Andere Module hören
--  NUR hier zu – egal ob Maus, Controller oder Touch.
--
--  Öffentliche API (§C7.5):
--    Controls.Bind(action, fn(state, input?), priority?): () -> ()    state "Begin" | "End" | "Change"
--    Controls.IsDown(action): boolean
--    Controls.Input(): "KBM" | "Gamepad" | "Touch"                    folgt UserInputService.PreferredInput (live)
--    Controls.SetContext(c)   "World" | "Vehicle" | "Terminal" | "Menu" | "Spectate"
--  Zusätzlich: Controls.Context(): string (wirksamer Kontext), Controls.Emit(action, state, source?) (virtuelle Eingabe),
--    Controls.Init(ctx), Controls.Start()
--  Aktionen: Interact, Terminal, Tower, Shop, Quests, Menu, Sprint, Boost, Handbrake, ChartTf, ChartType, React,
--    AdminPanel, Fly, Spectate, Debug, PhotoMode.
--  Kontext-Regeln: Terminal-Fenster offen -> "Terminal"; anderes Fenster offen -> "Menu"; Auto -> "Vehicle"
--  (Hooks "Vehicle:Enter"/"Vehicle:Exit"). Interact wird nie verschluckt (ProximityPrompts bleiben bedienbar).
--  Sprinten ist hier eingebaut (WalkSpeed aus Config.Client.Movement, fremde Werte – z. B. Admin-Speed – bleiben).
--  Hook "Input"(kind) bei jedem Wechsel der Eingabe-Art.
-- =====================================================================

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Controls = {}

type State = "Begin" | "End" | "Change"
type Listener = { Fn: (State, InputObject?) -> (), Priority: number, Order: number, Alive: boolean }

local player = Players.LocalPlayer

local ACTIONS = {
	"Interact",
	"Terminal",
	"Tower",
	"Shop",
	"Quests",
	"Menu",
	"Sprint",
	"Boost",
	"Handbrake",
	"ChartTf",
	"ChartType",
	"React",
	"AdminPanel",
	"Fly",
	"Spectate",
	"Debug",
	"PhotoMode",
}

local function set(list: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, name in ipairs(list) do
		result[name] = true
	end
	return result
end

-- Welche Aktionen in welchem Kontext wirken (alles andere wird an Roblox weitergereicht)
local ALWAYS = { "Menu", "AdminPanel", "Fly", "Spectate", "Debug", "PhotoMode" }
local function withAlways(list: { string }): { [string]: boolean }
	local result = set(list)
	for _, name in ipairs(ALWAYS) do
		result[name] = true
	end
	return result
end

local CONTEXT_ACTIONS: { [string]: { [string]: boolean } } = {
	World = withAlways({ "Interact", "Terminal", "Tower", "Shop", "Quests", "Sprint", "React" }),
	Vehicle = withAlways({ "Interact", "Terminal", "Tower", "Shop", "Quests", "Boost", "Handbrake" }),
	Terminal = withAlways({ "Terminal", "ChartTf", "ChartType" }),
	Menu = withAlways({ "Terminal", "Tower", "Shop", "Quests" }),
	Spectate = withAlways({}),
}
-- Diese Aktionen "verschlucken" die Eingabe in ihrem Kontext (Leertaste = Handbremse statt Aussteigen,
-- Shift = Sprint/Boost statt Shift-Lock links; ProximityPrompts (Interact) werden nie verschluckt)
local SINK: { [string]: { [string]: boolean } } = {
	World = { Sprint = true },
	Vehicle = { Boost = true, Handbrake = true },
	Terminal = { ChartTf = true, ChartType = true },
}

local BASE_PRIORITY = Enum.ContextActionPriority.High.Value

local ctx: any = nil
local listeners: { [string]: { Listener } } = {}
local listenerOrder = 0
local held: { [string]: { [string]: boolean } } = {} -- [action][quelle] = true
local downState: { [string]: boolean } = {}
local baseContext = "World"
local lastEffective = "World"
local inVehicle = false
local inputKind: "KBM" | "Gamepad" | "Touch" = "KBM"

-- Sprinten (eingebaut)
local sprintApplied: number? = nil -- zuletzt von uns gesetzte WalkSpeed (nur die setzen wir zurück)

-- ---------------------------------------------------------------------
-- KONTEXT
-- ---------------------------------------------------------------------
local function windows(): any
	return ctx and ctx.Windows
end

local function terminalOpen(): boolean
	local w = windows()
	if w and type(w.IsOpen) == "function" then
		local ok, open = pcall(w.IsOpen, "Terminal")
		return ok and open == true
	end
	return false
end

local function anyWindowOpen(): boolean
	local ui = ctx and ctx.UI
	if ui and type(ui.IsAnyWindowOpen) == "function" then
		local ok, open = pcall(ui.IsAnyWindowOpen)
		return ok and open == true
	end
	return false
end

function Controls.Context(): string
	if baseContext == "Spectate" then
		return "Spectate"
	end
	if baseContext == "Terminal" or terminalOpen() then
		return "Terminal"
	end
	if baseContext == "Menu" or anyWindowOpen() then
		return "Menu"
	end
	if inVehicle or baseContext == "Vehicle" then
		return "Vehicle"
	end
	return "World"
end

local function allowed(action: string, context: string?): boolean
	local actions = CONTEXT_ACTIONS[context or Controls.Context()]
	return actions ~= nil and actions[action] == true
end

local function dispatch(action: string, state: State, input: InputObject?)
	local list = listeners[action]
	if not list or #list == 0 then
		return
	end
	local snapshot = table.clone(list)
	for _, entry in ipairs(snapshot) do
		if entry.Alive then
			local ok, err = pcall(entry.Fn, state, input)
			if not ok then
				warn(("[Controls] Fehler in %s-Listener: %s"):format(action, tostring(err)))
			end
		end
	end
end

-- Quelle drückt/lässt los -> Begin/End nur beim Wechsel des Gesamtzustands
local function setHeld(action: string, source: string, down: boolean, input: InputObject?)
	local sources = held[action]
	if not sources then
		sources = {}
		held[action] = sources
	end
	if down then
		sources[source] = true
	else
		sources[source] = nil
	end
	local isDown = next(sources) ~= nil
	if isDown ~= (downState[action] == true) then
		downState[action] = isDown
		dispatch(action, if isDown then "Begin" else "End", input)
	end
end

-- Kontextwechsel: Aktionen, die jetzt gesperrt sind, sauber loslassen (nichts bleibt "hängen")
local function releaseBlocked()
	local effective = Controls.Context()
	if effective == lastEffective then
		return
	end
	lastEffective = effective
	for action, isDown in pairs(downState) do
		if isDown and not allowed(action, effective) then
			held[action] = {}
			downState[action] = false
			dispatch(action, "End", nil)
		end
	end
end

function Controls.SetContext(c: string)
	if CONTEXT_ACTIONS[c] == nil then
		warn("[Controls] Unbekannter Kontext: " .. tostring(c))
		return
	end
	baseContext = c
	releaseBlocked()
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH: Bind / IsDown / Emit / Input
-- ---------------------------------------------------------------------
function Controls.Bind(action: string, fn: (State, InputObject?) -> (), priority: number?): () -> ()
	if type(action) ~= "string" or type(fn) ~= "function" then
		warn("[Controls] Bind: Aktion (string) und Funktion erwartet")
		return function() end
	end
	local list = listeners[action]
	if not list then
		list = {}
		listeners[action] = list
	end
	listenerOrder += 1
	local entry: Listener = { Fn = fn, Priority = priority or 0, Order = listenerOrder, Alive = true }
	table.insert(list, entry)
	-- höhere Priorität zuerst, bei Gleichstand der zuerst angemeldete
	table.sort(list, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority > b.Priority
		end
		return a.Order < b.Order
	end)
	return function()
		if not entry.Alive then
			return
		end
		entry.Alive = false
		local current = listeners[action]
		if current then
			local index = table.find(current, entry)
			if index then
				table.remove(current, index)
			end
		end
	end
end

function Controls.IsDown(action: string): boolean
	return downState[action] == true
end

function Controls.Input(): "KBM" | "Gamepad" | "Touch"
	return inputKind
end

-- Virtuelle Eingabe (Touch-Knöpfe, automatisches Sprinten am Stick): gleiche Regeln wie echte Tasten
function Controls.Emit(action: string, state: State, source: string?)
	if type(action) ~= "string" then
		return
	end
	local key = "virtual:" .. (source or "touch")
	if state == "Begin" then
		if allowed(action) then
			setHeld(action, key, true, nil)
		end
	elseif state == "End" then
		setHeld(action, key, false, nil)
	elseif state == "Change" and allowed(action) then
		dispatch(action, "Change", nil)
	end
end

-- ---------------------------------------------------------------------
-- CONTEXTACTIONSERVICE
-- ---------------------------------------------------------------------
local function enumFromName(name: string): (Enum.KeyCode | Enum.UserInputType)?
	local key = Enum.KeyCode:FromName(name)
	if key then
		return key
	end
	return Enum.UserInputType:FromName(name)
end

local function sourceOf(input: InputObject): string
	if input.KeyCode.Name ~= "Unknown" then
		return input.KeyCode.Name
	end
	return input.UserInputType.Name
end

local function typingInTextBox(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function handle(action: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local source = sourceOf(input)
	local ending = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if typingInTextBox() then
		-- beim Tippen keine Aktionen auslösen – aber Loslassen trotzdem zählen (sonst klebt z. B. Sprint, wenn man
		-- Shift hält, ins Chat-/Betragsfeld klickt und dort loslässt)
		if ending then
			setHeld(action, source, false, input)
		end
		return Enum.ContextActionResult.Pass
	end
	local context = Controls.Context()
	-- In Fenstern navigiert das Steuerkreuz die Oberfläche (GuiService) – dort keine Fenster-Kürzel vom D-Pad
	local dpadInMenu = context == "Menu" and string.sub(input.KeyCode.Name, 1, 4) == "DPad"
	if dpadInMenu or not allowed(action, context) then
		-- gesperrt: evtl. gehaltene Quelle trotzdem loslassen
		if ending then
			setHeld(action, source, false, input)
		end
		return Enum.ContextActionResult.Pass
	end
	local sinks = SINK[context]
	local result = if sinks and sinks[action] then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	if inputState == Enum.UserInputState.Begin then
		setHeld(action, source, true, input)
	elseif ending then
		setHeld(action, source, false, input)
	elseif inputState == Enum.UserInputState.Change then
		dispatch(action, "Change", input)
	end
	return result
end

local function bindAll()
	local config = ctx.Config
	local client = config and config.Client or {}
	local keys: { [string]: { string } } = client.Keys or {}
	local pad: { [string]: any } = client.Gamepad or {}
	for index, action in ipairs(ACTIONS) do
		local inputs: { Enum.KeyCode | Enum.UserInputType } = {}
		local seen: { [string]: boolean } = {}
		local function add(name: any)
			if type(name) ~= "string" or seen[name] then
				return
			end
			local value = enumFromName(name)
			if value then
				seen[name] = true
				table.insert(inputs, value)
			end
		end
		for _, name in ipairs(keys[action] or {}) do
			add(name)
		end
		local padValue = pad[action]
		if type(padValue) == "table" then
			for _, name in ipairs(padValue) do
				add(name)
			end
		else
			add(padValue)
		end
		if #inputs > 0 then
			-- spätere Aktionen leicht niedriger (gleiche Taste: der nicht erlaubte Eintrag reicht weiter)
			local priority = BASE_PRIORITY + (#ACTIONS - index)
			ContextActionService:BindActionAtPriority("AT_" .. action, function(_, state, input)
				return handle(action, state, input)
			end, false, priority, table.unpack(inputs))
		end
	end
end

-- ---------------------------------------------------------------------
-- SPRINTEN (eingebaut): Lauf-Geschwindigkeit nur dann setzen/zurücksetzen, wenn niemand anderes sie geändert hat
-- ---------------------------------------------------------------------
local function movement(): (number, number)
	local config = ctx and ctx.Config
	local move = config and config.Client and config.Client.Movement
	local walk = move and tonumber(move.WalkSpeed) or 16
	local sprint = move and tonumber(move.SprintSpeed) or 24
	return walk, math.max(walk, sprint)
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function applySprint(on: boolean)
	local hum = humanoid()
	if not hum then
		sprintApplied = nil
		return
	end
	local walk, sprint = movement()
	if on then
		-- nur von der normalen Geschwindigkeit aus (Admin-Speed, Jetpack o. Ä. bleiben unberührt)
		if math.abs(hum.WalkSpeed - walk) < 0.01 then
			hum.WalkSpeed = sprint
			sprintApplied = sprint
		end
	else
		if sprintApplied and math.abs(hum.WalkSpeed - sprintApplied) < 0.01 then
			hum.WalkSpeed = walk
		end
		sprintApplied = nil
	end
end

-- ---------------------------------------------------------------------
-- EINGABE-ART (Maus/Tastatur, Controller, Touch) – live
-- ---------------------------------------------------------------------
local function computeInput(): "KBM" | "Gamepad" | "Touch"
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and preferred then
		if preferred == Enum.PreferredInput.Touch then
			return "Touch"
		elseif preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad then
			return "Gamepad"
		end
		return "KBM"
	end
	-- Rückfall: letzte Eingabe
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.sub(last.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "KBM"
end

local function updateInput(force: boolean?)
	local kind = computeInput()
	if kind ~= inputKind or force then
		inputKind = kind
		ctx.Hooks.Fire("Input", kind)
	end
end

local function releaseAll()
	for action, isDown in pairs(downState) do
		if isDown then
			held[action] = {}
			downState[action] = false
			dispatch(action, "End", nil)
		end
	end
end

function Controls.Init(context: any)
	ctx = context
	inputKind = computeInput()
	local hooks = ctx.Hooks
	hooks.On("WindowOpened", releaseBlocked)
	hooks.On("WindowClosed", releaseBlocked)
	-- Auto (WP7 Vehicles feuert die Hooks): Kontext "Vehicle"
	hooks.On("Vehicle:Enter", function()
		inVehicle = true
		releaseBlocked()
	end)
	hooks.On("Vehicle:Exit", function()
		inVehicle = false
		releaseBlocked()
	end)
	-- eingebautes Sprinten (andere Module können zusätzlich auf "Sprint" hören)
	Controls.Bind("Sprint", function(state)
		if state == "Begin" then
			applySprint(true)
		elseif state == "End" then
			applySprint(false)
		end
	end, -100)
end

function Controls.Start()
	bindAll()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		updateInput(false)
	end)
	-- Rückfall, falls PreferredInput auf einem Gerät nicht wechselt
	UserInputService.LastInputTypeChanged:Connect(function()
		updateInput(false)
	end)
	updateInput(true)
	-- neuer Charakter: nichts darf gedrückt bleiben (auch kein Sprint-Rest)
	player.CharacterAdded:Connect(function()
		sprintApplied = nil
		releaseAll()
	end)
	-- Fenster verlieren den Fokus (Alt-Tab): gehaltene Tasten lösen
	UserInputService.WindowFocusReleased:Connect(releaseAll)
end

return Controls
