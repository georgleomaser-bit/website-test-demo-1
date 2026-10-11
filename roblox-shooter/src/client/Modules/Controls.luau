-- =====================================================================
--  CLUTCH CLASH – Eingabe-Belegung über ContextActionService (Client/Modules/Controls)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.4, B15.1.
--
--  Alle Tasten/Knöpfe aus Config.Client.Keys (PC) und Config.Client.Gamepad laufen über
--  ContextActionService:BindActionAtPriority (createTouchButton = false). Eigene Touch-Knöpfe
--  (Modul TouchControls) speisen dieselben Aktionen über Controls.Emit ein. Andere Module hören
--  NUR hier zu – egal ob Maus, Controller oder Touch.
--
--  Öffentliche API:
--    Controls.Bind(action, fn(state, input?), priority?): () -> ()    state "Begin" | "End" | "Change"
--    Controls.IsDown(action): boolean
--    Controls.Input(): "KBM" | "Gamepad" | "Touch"                    folgt UserInputService.PreferredInput (live)
--    Controls.SetContext(c)   "Lobby" | "Match" | "Range" | "Menu" | "Spectate"
--    Controls.Context(): string                                        wirksamer Kontext (Fenster offen = "Menu")
--    Controls.Emit(action, state, source?)                             virtuelle Eingabe (Touch-Knöpfe)
--    Controls.Init(ctx) / Controls.Start()
--  Aktionen: Fire, Ads, Reload, Slot1..Slot4, NextWeapon, PrevWeapon, LastWeapon, Melee, Utility, Sprint, Slide,
--  Inspect, Scoreboard, Loadout, Menu, Ready, AdminPanel, Fly, SpecNext, SpecPrev (+ Spectate, Debug für Admins).
--  Fenster offen -> Kampf-Eingaben gesperrt (Kontext "Menu"). Hook "Input"(kind) bei jedem Wechsel.
-- =====================================================================

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Controls = {}

type State = "Begin" | "End" | "Change"
type Listener = { Fn: (State, InputObject?) -> (), Priority: number, Order: number, Alive: boolean }

local ACTIONS = {
	"Fire",
	"Ads",
	"Reload",
	"Slot1",
	"Slot2",
	"Slot3",
	"Slot4",
	"NextWeapon",
	"PrevWeapon",
	"LastWeapon",
	"Melee",
	"Utility",
	"Sprint",
	"Slide",
	"Inspect",
	"Scoreboard",
	"Loadout",
	"Menu",
	"Ready",
	"AdminPanel",
	"Fly",
	"SpecNext",
	"SpecPrev",
	"Spectate",
	"Debug",
}

local function set(list: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, name in ipairs(list) do
		result[name] = true
	end
	return result
end

-- Welche Aktionen in welchem Kontext wirken (alles andere wird an Roblox weitergereicht)
local ALWAYS = { "Menu", "AdminPanel", "Fly", "Spectate", "Debug" }
local COMBAT = {
	"Fire",
	"Ads",
	"Reload",
	"Slot1",
	"Slot2",
	"Slot3",
	"Slot4",
	"NextWeapon",
	"PrevWeapon",
	"LastWeapon",
	"Melee",
	"Utility",
	"Sprint",
	"Slide",
	"Inspect",
	"Scoreboard",
	"Loadout",
	"Ready",
}
local function withAlways(list: { string }): { [string]: boolean }
	local result = set(list)
	for _, name in ipairs(ALWAYS) do
		result[name] = true
	end
	return result
end

local RANGE = withAlways(COMBAT)
RANGE.Ready = nil -- in der Range gibt es kein "Bereit" -> Start/Enter bleibt "Menü"

local CONTEXT_ACTIONS: { [string]: { [string]: boolean } } = {
	Match = withAlways(COMBAT),
	Range = RANGE,
	Lobby = withAlways({ "Sprint", "Slide", "Loadout" }),
	Spectate = withAlways({ "SpecNext", "SpecPrev", "Scoreboard", "Ready" }),
	Menu = withAlways({}),
}
-- In diesen Kontexten "verschluckt" eine benutzte Taste die Eingabe (z. B. Mausrad zoomt nicht raus)
local SINK_CONTEXTS = { Match = true, Range = true, Spectate = true }

local BASE_PRIORITY = Enum.ContextActionPriority.High.Value
local SLOT_OF_NAME: { [string]: string } = {
	Primary = "Slot1",
	Secondary = "Slot2",
	Melee = "Slot3",
	Utility = "Slot4",
}
local SLOT_OF_NUMBER = { "Slot1", "Slot2", "Slot3", "Slot4" }

local ctx: any = nil
local listeners: { [string]: { Listener } } = {}
local listenerOrder = 0
local held: { [string]: { [string]: boolean } } = {} -- [action][quelle] = true
local downState: { [string]: boolean } = {}
local baseContext = "Lobby"
local lastEffective = "Lobby"
local inputKind: "KBM" | "Gamepad" | "Touch" = "KBM"
local triggerDown: { [string]: boolean } = {} -- "ButtonR2"/"ButtonL2" analog
local currentSlot: string? = nil -- zuletzt ausgerüsteter Slot ("Slot1".."Slot4"), aus Hook "Equip"
local previousSlot: string? = nil
local cycleAt = -math.huge
local cycleRestore: string? = nil

-- ---------------------------------------------------------------------
-- KONTEXT
-- ---------------------------------------------------------------------
local function windowOpen(): boolean
	local ui = ctx and ctx.UI
	if ui and type(ui.IsAnyWindowOpen) == "function" then
		local ok, open = pcall(ui.IsAnyWindowOpen)
		return ok and open == true
	end
	return false
end

function Controls.Context(): string
	if windowOpen() then
		return "Menu"
	end
	return baseContext
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
	table.clear(triggerDown) -- Abzüge neu bewerten (sonst bleibt ein "gedrückt" hängen)
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
-- ÖFFENTLICH: Bind / IsDown / Emit
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

local function triggerThreshold(): number
	local config = ctx and ctx.Config
	local pad = config and config.Client and config.Client.Gamepad
	local value = pad and pad.TriggerThreshold
	return if type(value) == "number" then value else 0.4
end

local function handle(action: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if typingInTextBox() then
		return Enum.ContextActionResult.Pass
	end
	local context = Controls.Context()
	local source = sourceOf(input)
	local ending = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if not allowed(action, context) then
		-- gesperrt: evtl. gehaltene Quelle trotzdem loslassen
		if ending then
			triggerDown[source] = nil
			setHeld(action, source, false, input)
		end
		return Enum.ContextActionResult.Pass
	end
	local sink = if SINK_CONTEXTS[context] then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass

	-- Mausrad: Waffe weiter/zurück (nur ein kurzer Begin/End-Puls)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local wheelAction = if input.Position.Z < 0 then "NextWeapon" else "PrevWeapon"
		if allowed(wheelAction, context) then
			dispatch(wheelAction, "Begin", input)
			dispatch(wheelAction, "End", input)
			return sink
		end
		return Enum.ContextActionResult.Pass
	end

	-- Analoge Abzüge: gedrückt ab Position.Z ≥ Schwelle (B15.1)
	if input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		local pressed: boolean
		if ending then
			pressed = false
		elseif inputState == Enum.UserInputState.Begin and input.Position.Z == 0 then
			pressed = true -- digitale Abzüge melden nur Begin/End
		else
			pressed = input.Position.Z >= triggerThreshold()
		end
		if pressed ~= (triggerDown[source] == true) then
			triggerDown[source] = pressed
			setHeld(action, source, pressed, input)
		end
		return sink
	end

	if inputState == Enum.UserInputState.Begin then
		setHeld(action, source, true, input)
	elseif ending then
		setHeld(action, source, false, input)
	elseif inputState == Enum.UserInputState.Change then
		dispatch(action, "Change", input)
	end
	return sink
end

-- Gamepad Y: Primär <-> Sekundär; zweimal schnell = letzte Waffe (relativ zur Waffe VOR dem ersten Tippen)
local function slotNow(): string?
	if currentSlot then
		return currentSlot
	end
	local weapon = ctx and ctx.Modules and ctx.Modules.WeaponClient
	if weapon and type(weapon.Current) == "function" then
		local ok, _key, def = pcall(weapon.Current)
		if ok and type(def) == "table" and type(def.Slot) == "string" then
			return SLOT_OF_NAME[def.Slot]
		end
	end
	return nil
end

local function pulse(action: string, input: InputObject?)
	if allowed(action) then
		dispatch(action, "Begin", input)
		dispatch(action, "End", input)
	end
end

local function handleCycle(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if typingInTextBox() then
		return Enum.ContextActionResult.Pass
	end
	local context = Controls.Context()
	if not allowed("Slot1", context) then
		return Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local config = ctx and ctx.Config
	local gap = config and config.Client and config.Client.Gamepad and config.Client.Gamepad.DoubleTap or 0.28
	local now = os.clock()
	if now - cycleAt <= gap then
		cycleAt = -math.huge
		local target = cycleRestore
		cycleRestore = nil
		if target and target ~= slotNow() then
			pulse(target, input)
		else
			pulse("LastWeapon", input)
		end
		return Enum.ContextActionResult.Sink
	end
	cycleAt = now
	cycleRestore = previousSlot
	local current = slotNow()
	pulse(if current == "Slot1" then "Slot2" else "Slot1", input)
	return Enum.ContextActionResult.Sink
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
		add(pad[action])
		if action == "NextWeapon" and client.WheelSwitch ~= false then
			add("MouseWheel")
		end
		if #inputs > 0 then
			-- Ready vor Menu (Start = Bereit im Match, sonst Menü); spätere Aktionen leicht niedriger
			local priority = BASE_PRIORITY + (#ACTIONS - index)
			if action == "Ready" then
				priority = BASE_PRIORITY + #ACTIONS + 5
			end
			ContextActionService:BindActionAtPriority("CC_" .. action, function(_, state, input)
				return handle(action, state, input)
			end, false, priority, table.unpack(inputs))
		end
	end
	local cycle = pad.Cycle
	local cycleKey = type(cycle) == "string" and Enum.KeyCode:FromName(cycle)
	if cycleKey then
		ContextActionService:BindActionAtPriority("CC_Cycle", handleCycle, false, BASE_PRIORITY, cycleKey)
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
	-- Rückfall (sehr alte Clients): letzte Eingabe
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

local function slotFrom(slot: any): string?
	if type(slot) == "number" then
		return SLOT_OF_NUMBER[slot]
	elseif type(slot) == "string" then
		return SLOT_OF_NAME[slot] or (if string.match(slot, "^Slot[1-4]$") then slot else nil)
	end
	return nil
end

function Controls.Init(context: any)
	ctx = context
	inputKind = computeInput()
	local hooks = ctx.Hooks
	-- Standard-Kontexte aus den Spiel-Ereignissen (WeaponClient kann jederzeit SetContext überschreiben)
	local armedCtx: string? = nil
	hooks.On("Armed", function(info)
		armedCtx = type(info) == "table" and info.Ctx or nil
		Controls.SetContext(if armedCtx == "Range" then "Range" else "Match")
	end)
	hooks.On("Disarmed", function()
		armedCtx = nil
		currentSlot, previousSlot = nil, nil
		Controls.SetContext("Lobby")
	end)
	hooks.On("Spectate", function(model)
		if model ~= nil then
			Controls.SetContext("Spectate")
		elseif armedCtx then
			Controls.SetContext(if armedCtx == "Range" then "Range" else "Match")
		end
	end)
	hooks.On("LocalRevived", function()
		if armedCtx then
			Controls.SetContext(if armedCtx == "Range" then "Range" else "Match")
		end
	end)
	hooks.On("Equip", function(slot)
		local name = slotFrom(slot)
		if name and name ~= currentSlot then
			previousSlot = currentSlot
			currentSlot = name
		end
	end)
	hooks.On("WindowOpened", releaseBlocked)
	hooks.On("WindowClosed", releaseBlocked)
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
	-- neuer Charakter: nichts darf gedrückt bleiben
	Players.LocalPlayer.CharacterAdded:Connect(function()
		table.clear(triggerDown)
		for action, isDown in pairs(downState) do
			if isDown then
				held[action] = {}
				downState[action] = false
				dispatch(action, "End", nil)
			end
		end
	end)
end

return Controls
