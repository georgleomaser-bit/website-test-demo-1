-- =====================================================================
--  CLUTCH CLASH – Einstellungen (Client/Modules/Settings)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.3 ("Settings"), C7.4, B15.3, C19 (Info).
--
--  Ein Fenster "Settings", gebaut aus Config.Client.SettingsSchema (jeder Schlüssel aus
--  DefaultSettings): Regler (Zahlen), Schalter (an/aus), Auswahl (Optionen) + Fadenkreuz-Vorschau.
--  Änderungen wirken sofort (Hook "Settings"), gespeichert wird gebündelt über Request
--  "SaveSettings" (nur geänderte Schlüssel, geklemmt wie auf dem Server). Fällt die Bildrate
--  5 s lang unter 35 FPS, schaltet sich "Reduzierte Effekte" einmal automatisch ein (mit Hinweis).
--  Info-Bereich: Regeln + Einspruch bei Banns (C19), Version.
--
--  Öffentliche API (C7.4):
--    Settings.Get(): { [string]: any }      aktuelle Werte (NICHT verändern – Settings.Set benutzen)
--  Zusätzlich: Settings.Set(key, value) (geklemmt, speichert), Settings.Fps(): number,
--    Settings.Open(), Settings.Frame(dt), Settings.Tick(), Settings.Init(ctx), Settings.Start()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any

local Settings = {}

local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local SAVE_DELAY = 0.8 -- Sekunden nach der letzten Änderung speichern (Server-Limit 2/s)
local WINDOW_W = 620
local WINDOW_H = 560

-- Reihenfolge + Abschnitte im Fenster (Schlüssel aus dem Schema; "Crosshair.<Feld>" = Teilwert)
local SECTIONS: { { Key: string, Color: Color3, Items: { string } } } = {
	{
		Key = "controls",
		Color = Theme.Orange,
		Items = {
			"SensMouse",
			"SensPad",
			"SensTouch",
			"AdsMult",
			"ScopeMult",
			"InvertY",
			"AdsToggle",
			"SprintToggle",
			"AutoReload",
			"AimAssist",
			"AutoFire",
		},
	},
	{
		Key = "crosshair",
		Color = Theme.Pink,
		Items = { "Crosshair.Style", "Crosshair.Color", "Crosshair.Size", "Crosshair.Gap", "Crosshair.Dot" },
	},
	{
		Key = "visual",
		Color = Theme.Cyan,
		Items = { "Fov", "EnemyColor", "DamageNumbers", "HitSound", "ReducedFx", "Shake", "ShowNet" },
	},
	{ Key = "touch", Color = Theme.Purple, Items = { "LeftHanded", "ButtonScale" } },
	{ Key = "audio", Color = Theme.Green, Items = { "Sfx", "Music", "Ui" } },
	{ Key = "game", Color = Theme.Yellow, Items = { "Lang", "AutoRequeue", "PublicDrops" } },
}
-- Regler, die als Prozent angezeigt werden
local PERCENT = {
	AimAssist = true,
	Shake = true,
	Sfx = true,
	Music = true,
	Ui = true,
	ButtonScale = true,
}

local ctx: any = nil
local schema: { [string]: any } = Config.Client and Config.Client.SettingsSchema or {}
local defaults: { [string]: any } = Config.Client and Config.Client.DefaultSettings or {}
local current: { [string]: any } = {}
local pending: { [string]: any } = {}
local saveToken = 0
local window: any = nil
local rows: { { Refresh: () -> () } } = {}
local rowConns: { RBXScriptConnection } = {} -- globale Eingabe-Verbindungen der Regler (beim Neubau trennen)
local builtLang = ""
local statusLabel: TextLabel? = nil

-- Bildrate + automatische Reduzierte Effekte
local fps = 60
local fpsAccum = 0
local fpsFrames = 0
local lowFor = 0
local startedAt = os.clock()
local autoDone = false
local focused = true

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

-- Text eines Schlüssels; fehlt er (Lang gibt den Schlüssel zurück), den Ersatz nehmen
local function TOr(key: string, fallback: string): string
	local text = T(key)
	if text == key then
		return fallback
	end
	return text
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Startwerte schon beim Laden (andere Module fragen Settings.Get evtl. vor Settings.Init)
current = deepCopy(defaults)

local function entryFor(path: string): (any, string, string?)
	local key, field = string.match(path, "^(%w+)%.(%w+)$")
	if key and field then
		local parent = schema[key]
		local fields = parent and parent.Fields
		return fields and fields[field], key, field
	end
	return schema[path], path, nil
end

-- Wert prüfen + klemmen wie der Server (Zahl: Min/Max/Step/Integer; Enum: Option; Bool)
local function clean(entry: any, value: any, fallback: any): any
	if type(entry) ~= "table" then
		return fallback
	end
	if entry.Type == "number" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		local v = math.clamp(value, entry.Min or value, entry.Max or value)
		local step = entry.Step
		if type(step) == "number" and step > 0 then
			local base = entry.Min or 0
			v = base + math.floor((v - base) / step + 0.5) * step
			v = math.clamp(v, entry.Min or v, entry.Max or v)
			v = math.floor(v * 1000 + 0.5) / 1000
		end
		if entry.Integer then
			v = math.floor(v + 0.5)
		end
		return v
	elseif entry.Type == "boolean" then
		return if type(value) == "boolean" then value else fallback
	elseif entry.Type == "enum" then
		return if type(value) == "string" and table.find(entry.Options or {}, value) then value else fallback
	elseif entry.Type == "table" then
		if type(value) ~= "table" then
			return fallback
		end
		local result = {}
		local fb = if type(fallback) == "table" then fallback else {}
		for field, sub in pairs(entry.Fields or {}) do
			result[field] = clean(sub, value[field], fb[field])
		end
		return result
	end
	return fallback
end

local function fire()
	ctx.Hooks.Fire("Settings", current)
end

-- ---------------------------------------------------------------------
-- SPEICHERN (gebündelt, nur geänderte Schlüssel)
-- ---------------------------------------------------------------------
local function setStatus(text: string, color: Color3?)
	local label = statusLabel
	if label then
		label.Text = text
		label.TextColor3 = color or WHITE
	end
end

local function flush()
	if next(pending) == nil then
		return
	end
	local batch = pending
	pending = {}
	local reply = ctx.RequestFull("SaveSettings", batch, true)
	if reply.Ok then
		setStatus(T("ui.set.saved"), Theme.Cash)
	else
		setStatus(T("ui.set.saveFailed"), Theme.Red)
		if type(reply.Message) == "string" and reply.Message ~= "" then
			UI.Toast(reply.Message, "Error")
		end
	end
	if batch.AutoRequeue ~= nil then
		ctx.RequestFull("AutoRequeue", batch.AutoRequeue == true, true)
	end
end

local function scheduleSave(key: string)
	pending[key] = deepCopy(current[key])
	saveToken += 1
	local token = saveToken
	setStatus(T("ui.set.saving"), Theme.SubText)
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			flush()
		end
	end)
end

function Settings.Get(): { [string]: any }
	return current
end

-- Wert setzen ("Key" oder "Crosshair.Feld"): geklemmt, sofort wirksam, gebündelt gespeichert
function Settings.Set(path: string, value: any)
	if type(path) ~= "string" then
		return
	end
	local entry, key, field = entryFor(path)
	if not entry then
		warn("[Settings] Unbekannte Einstellung: " .. path)
		return
	end
	if field then
		local parent = current[key]
		if type(parent) ~= "table" then
			parent = deepCopy(defaults[key]) or {}
			current[key] = parent
		end
		local cleaned = clean(entry, value, parent[field])
		if parent[field] == cleaned then
			return
		end
		parent[field] = cleaned
	else
		local cleaned = clean(entry, value, current[key])
		if current[key] == cleaned and type(cleaned) ~= "table" then
			return
		end
		current[key] = cleaned
	end
	scheduleSave(key)
	fire()
	for _, row in ipairs(rows) do
		row.Refresh()
	end
end

function Settings.Fps(): number
	return fps
end

-- Server-Stand übernehmen (lokal noch nicht gespeicherte Änderungen bleiben)
local function mergeServer(serverSettings: any)
	if type(serverSettings) ~= "table" then
		return
	end
	local changed = false
	for key, entry in pairs(schema) do
		if pending[key] == nil and serverSettings[key] ~= nil then
			local cleaned = clean(entry, serverSettings[key], current[key])
			if type(cleaned) == "table" or cleaned ~= current[key] then
				current[key] = cleaned
				changed = true
			end
		end
	end
	if changed then
		fire()
		for _, row in ipairs(rows) do
			row.Refresh()
		end
	end
end

-- ---------------------------------------------------------------------
-- FENSTER-BAUSTEINE
-- ---------------------------------------------------------------------
local function labelFor(path: string): string
	return TOr("ui.set." .. path, path)
end

local function optionText(path: string, option: any): string
	local _, key, field = entryFor(path)
	local name = field or key
	return TOr("ui.opt." .. name .. "." .. tostring(option), tostring(option))
end

local function getValue(path: string): any
	local _, key, field = entryFor(path)
	if field then
		local parent = current[key]
		return type(parent) == "table" and parent[field] or nil
	end
	return current[key]
end

local function formatNumber(path: string, entry: any, value: number): string
	local _, key = entryFor(path)
	if PERCENT[key] then
		return tostring(math.floor(value * 100 + 0.5)) .. " %"
	end
	if entry.Integer then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.2f", value)
end

local function makeRow(parent: Instance, order: number): (Frame, Frame)
	-- eigene Zeile ohne Listen-Layout (Beschriftung links, Bedienelement rechtsbündig)
	local row: Frame = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local label = UI.Label({
		Size = UDim2.new(0.5, -6, 1, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		Outline = 2,
		Parent = row,
	})
	label.Name = "Label"
	local control = UI.Create("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	return row, control
end

local function boolRow(parent: Instance, order: number, path: string)
	local row, control = makeRow(parent, order)
	local button = UI.Button({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Color = Theme.Gray,
		MaxText = 20,
		Parent = control,
	}, function()
		Settings.Set(path, not (getValue(path) == true))
	end)
	local label = row:FindFirstChild("Label") :: TextLabel
	table.insert(rows, {
		Refresh = function()
			label.Text = labelFor(path)
			local on = getValue(path) == true
			button.SetText(if on then T("ui.on") else T("ui.off"))
			button.SetColor(if on then Theme.Green else Theme.Gray)
		end,
	})
end

local function enumRow(parent: Instance, order: number, path: string, entry: any)
	local row, control = makeRow(parent, order)
	local options: { any } = entry.Options or {}
	local isNumberChoice = entry.Type == "number" -- z. B. Fadenkreuz-Stil 1..4
	if isNumberChoice then
		options = {}
		for v = entry.Min or 1, entry.Max or 1 do
			table.insert(options, v)
		end
	end
	local button = UI.Button({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Color = Theme.Blue,
		MaxText = 20,
		Parent = control,
	}, function()
		local value = getValue(path)
		local index = table.find(options, value) or 0
		local nextValue = options[index % math.max(1, #options) + 1]
		if nextValue ~= nil then
			Settings.Set(path, nextValue)
		end
	end)
	local label = row:FindFirstChild("Label") :: TextLabel
	table.insert(rows, {
		Refresh = function()
			label.Text = labelFor(path)
			button.SetText("◀ " .. optionText(path, getValue(path)) .. " ▶")
		end,
	})
end

local function numberRow(parent: Instance, order: number, path: string, entry: any)
	local row, control = makeRow(parent, order)
	local minV: number = entry.Min or 0
	local maxV: number = entry.Max or 1
	local step: number = entry.Step or ((maxV - minV) / 20)
	local function nudge(direction: number)
		local value = tonumber(getValue(path)) or minV
		Settings.Set(path, value + direction * step)
	end
	UI.Button({
		Size = UDim2.new(0, 40, 1, 0),
		Text = "−",
		Color = Theme.Red,
		MaxText = 26,
		Parent = control,
	}, function()
		nudge(-1)
	end)
	UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 40, 1, 0),
		Text = "+",
		Color = Theme.Green,
		MaxText = 26,
		Parent = control,
	}, function()
		nudge(1)
	end)
	-- Regler-Schiene zum Ziehen (Maus/Touch)
	local track: Frame = UI.Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -96, 0, 26),
		BackgroundColor3 = Theme.PanelDark:Lerp(BLACK, 0.4),
		Active = true,
		Parent = control,
	}, { UI.Corner(10), UI.Stroke(BLACK, 2) })
	local fill: Frame = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Yellow,
		Parent = track,
	}, { UI.Corner(10) })
	local valueLabel = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = UI.Fonts.Number,
		MaxText = 18,
		Outline = 2,
		ZIndex = 2,
		Parent = track,
	})
	local dragging: InputObject? = nil
	local function setFromX(x: number)
		local absPos = track.AbsolutePosition.X
		local width = math.max(1, track.AbsoluteSize.X)
		local ratio = math.clamp((x - absPos) / width, 0, 1)
		Settings.Set(path, minV + (maxV - minV) * ratio)
	end
	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = input
			setFromX(input.Position.X)
		end
	end)
	table.insert(rowConns, UserInputService.InputChanged:Connect(function(input: InputObject)
		local active = dragging
		if not active or not track.Parent then
			return
		end
		if
			(
				active.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			) or input == active
		then
			setFromX(input.Position.X)
		end
	end))
	table.insert(
		rowConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == dragging then
				dragging = nil
			end
		end)
	)
	local label = row:FindFirstChild("Label") :: TextLabel
	table.insert(rows, {
		Refresh = function()
			label.Text = labelFor(path)
			local value = tonumber(getValue(path)) or minV
			local ratio = if maxV > minV then (value - minV) / (maxV - minV) else 0
			fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
			valueLabel.Text = formatNumber(path, entry, value)
		end,
	})
end

local function clearContent(content: ScrollingFrame)
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(rows)
	for _, conn in ipairs(rowConns) do
		conn:Disconnect()
	end
	table.clear(rowConns)
end

local function buildContent()
	local win = window
	if not win then
		return
	end
	local content: ScrollingFrame = win.Content
	clearContent(content)
	builtLang = ctx.Lang_()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	statusLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = T("ui.set.hint"),
		TextColor3 = Theme.SubText,
		MaxText = 18,
		Outline = 2,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	for _, section in ipairs(SECTIONS) do
		UI.Section(content, T("ui.sec." .. section.Key), nextOrder(), section.Color)
		if section.Key == "crosshair" then
			local combatHud = ctx.Modules.CombatHud
			if combatHud and type(combatHud.MakePreview) == "function" then
				local ok, preview = pcall(combatHud.MakePreview, content)
				if ok and typeof(preview) == "Instance" and preview:IsA("GuiObject") then
					preview.LayoutOrder = nextOrder()
				end
			end
		end
		for _, path in ipairs(section.Items) do
			local entry = entryFor(path)
			if entry then
				local isChoice = entry.Type == "enum" or path == "Crosshair.Style"
				if entry.Type == "boolean" then
					boolRow(content, nextOrder(), path)
				elseif isChoice then
					enumRow(content, nextOrder(), path, entry)
				elseif entry.Type == "number" then
					numberRow(content, nextOrder(), path, entry)
				end
			end
		end
	end
	-- Info: Regeln + Einspruch (C19) + Version
	UI.Section(content, T("ui.sec.info"), nextOrder(), Theme.Gray)
	for _, key in ipairs({ "ui.info.rules", "ui.info.appeal" }) do
		UI.Label({
			Size = UDim2.new(1, 0, 0, 64),
			Text = T(key),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 17,
			Outline = 2,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
	end
	local config = ctx.Config
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = T("core.version", tostring(config and config.Version or "?")),
		TextColor3 = Theme.SubText,
		MaxText = 16,
		Outline = 2,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	for _, row in ipairs(rows) do
		row.Refresh()
	end
end

local function openWindow()
	if not window then
		window = UI.Window(T("ui.settingsTitle"), WINDOW_W, WINDOW_H, Theme.Blue)
		buildContent()
	elseif builtLang ~= ctx.Lang_() then
		buildContent()
	else
		for _, row in ipairs(rows) do
			row.Refresh()
		end
	end
	UI.OpenWindow(window)
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Settings.Open()
	ctx.Windows.Open("Settings")
end

-- ---------------------------------------------------------------------
-- FRAME (Bildrate) / TICK
-- ---------------------------------------------------------------------
function Settings.Frame(dt: number)
	if not focused or dt <= 0 then
		return
	end
	fpsAccum += dt
	fpsFrames += 1
	if fpsAccum < 0.5 then
		return
	end
	fps = fpsFrames / fpsAccum
	local window_ = fpsAccum
	fpsAccum = 0
	fpsFrames = 0
	local config = ctx.Config
	local auto = config and config.Client and config.Client.AutoReducedFx or {}
	local threshold = tonumber(auto.Fps) or 35
	local needed = tonumber(auto.Seconds) or 5
	local delay = tonumber(auto.StartDelay) or 15
	if autoDone or current.ReducedFx == true or os.clock() - startedAt < delay then
		lowFor = 0
		return
	end
	if fps < threshold then
		lowFor += window_
		if lowFor >= needed then
			autoDone = true
			Settings.Set("ReducedFx", true)
			UI.Toast(T("ui.autoReduced"), "Info")
		end
	else
		lowFor = 0
	end
end

function Settings.Tick()
	-- Sprache gewechselt, während das Fenster zu ist: beim nächsten Öffnen neu bauen (siehe openWindow)
	local win = window
	if win and win.IsOpen and builtLang ~= ctx.Lang_() then
		buildContent()
	end
end

function Settings.Init(context: any)
	ctx = context
	local initialState = ctx.State
	if type(initialState) == "table" and type(initialState.Settings) == "table" then
		mergeServer(initialState.Settings)
	end
	ctx.Windows.Register("Settings", openWindow, closeWindow)

	local hooks = ctx.Hooks
	hooks.On("State", function(newState, changed)
		if type(changed) == "table" and changed.Settings and type(newState) == "table" then
			mergeServer(newState.Settings)
		end
	end)
	-- Menü-Taste (M / Start / ⚙️-Knopf): offenes Fenster schließen, sonst Einstellungen öffnen
	local controls = ctx.Modules.Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("Menu", function(state)
			if state ~= "Begin" then
				return
			end
			if ctx.Windows.IsOpen() then
				ctx.Windows.Close()
			else
				ctx.Windows.Open("Settings")
			end
		end)
	end
	local hud = ctx.Modules.Hud
	if hud and type(hud.AddRightButton) == "function" then
		hud.AddRightButton("⚙️", "ui.btn.settings", Theme.Gray, 90, function()
			ctx.Windows.Toggle("Settings")
		end)
	end
	UserInputService.WindowFocused:Connect(function()
		focused = true
		fpsAccum, fpsFrames, lowFor = 0, 0, 0
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		focused = false
	end)
end

function Settings.Start()
	startedAt = os.clock()
	fire() -- alle Module bekommen die Startwerte
end

return Settings
