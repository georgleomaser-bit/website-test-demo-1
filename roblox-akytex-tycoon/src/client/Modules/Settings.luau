-- =====================================================================
--  AKYTEX TYCOON – Einstellungen (Client/Modules/Settings)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.3 (Fenster "Settings"), §C7.5, §C14.2, §A2 (Info).
--  Basis: CC-Settings (schema-gesteuert, REUSE §1.4 ADAPT).
--
--  Ein Fenster "Settings", gebaut aus Config.Client.SettingsSchema: Regler (Zahlen), Schalter (an/aus), Auswahl
--  (Optionen). Änderungen wirken sofort (Hook "Settings"), gespeichert wird gebündelt über Request "SaveSettings"
--  (nur geänderte Schlüssel, 0,8 s nach der letzten Änderung; der Server klemmt mit demselben Schema).
--  "AutoTransfer" schickt zusätzlich Request "TradeAuto" { On } (Depot-Seite, WP4).
--  Abschnitte: Spiel · Grafik · Ton · Trading · Touch · Info (Disclaimer §A2, Regeln, Einspruch, Version, Fotomodus).
--  Taste M / Start / HUD-Knopf: offenes Fenster schließen, sonst Einstellungen öffnen.
--  AKYTEX-Look: Glas-Fenster (UI.Window), jede Einstellung eine Zeile auf Surface2 mit 1-px-Rahmen,
--  Schalter als Pill (an = Accent), Regler mit Accent-Füllung, Auswahl als Sekundär-Knopf.
--
--  Öffentliche API (§C7.5):
--    Settings.Get(): { [string]: any }      aktuelle Werte (NICHT verändern – Settings.Set benutzen)
--    Settings.Set(path, value)              "Key" oder "Key.Feld" (z. B. "Indicators.RSI"); geklemmt, gespeichert
--    Settings.Open()
--  Zusätzlich: Settings.Tick(), Settings.Init(ctx), Settings.Start()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any

local Settings = {}

local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)
local SWITCH_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local SAVE_DELAY = 0.8 -- Sekunden nach der letzten Änderung speichern (Server-Limit 2/s)
local WINDOW_W = 640
local WINDOW_H = 580
local ROW_H = 48

-- Reihenfolge + Abschnitte im Fenster (Schlüssel aus dem Schema)
local SECTIONS: { { Key: string, Items: { string } } } = {
	{ Key = "game", Items = { "Lang", "NumberStyle", "AutoTransfer", "NewsCards", "TickerBar" } },
	{ Key = "graphics", Items = { "Quality", "ReducedFx", "Shake", "ShowNet" } },
	{ Key = "audio", Items = { "Sfx", "Music", "Ui" } },
	{ Key = "trading", Items = { "ChartType", "ChartTf", "Colorblind" } },
	{ Key = "touch", Items = { "LeftHanded", "ButtonScale" } },
}
-- Regler, die als Prozent angezeigt werden
local PERCENT = {
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
local rowConns: { RBXScriptConnection } = {} -- Eingabe-Verbindungen der Regler (beim Neubau trennen)
local builtLang = ""
local statusLabel: TextLabel? = nil
local qualityLabel: TextLabel? = nil

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

-- Wert prüfen + klemmen wie der Server (Zahl: Min/Max/Step/Integer; Enum: Option; Bool; Tabelle: je Feld)
local function clean(entry: any, value: any, fallback: any): any
	if type(entry) ~= "table" then
		return fallback
	end
	if entry.Type == "number" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		local v = value
		local step = entry.Step
		if type(step) == "number" and step > 0 then
			v = math.floor(v / step + 0.5) * step
			v = math.floor(v * 1000 + 0.5) / 1000
		end
		if entry.Integer then
			v = math.floor(v + 0.5)
		end
		return math.clamp(v, entry.Min or v, entry.Max or v)
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
			local cleaned = clean(sub, value[field], fb[field])
			if cleaned ~= nil then
				result[field] = cleaned
			end
		end
		return result
	end
	return fallback
end

local function fire()
	ctx.Hooks.Fire("Settings", current)
end

local function refreshRows()
	for _, row in ipairs(rows) do
		row.Refresh()
	end
end

-- ---------------------------------------------------------------------
-- SPEICHERN (gebündelt, nur geänderte Schlüssel)
-- ---------------------------------------------------------------------
local function setStatus(text: string, color: Color3?)
	local label = statusLabel
	if label then
		label.Text = text
		label.TextColor3 = color or Theme.Text2
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
		setStatus(T("ui.set.saved"), Theme.Up)
	else
		setStatus(T("ui.set.saveFailed"), Theme.Down)
		if type(reply.Message) == "string" and reply.Message ~= "" then
			UI.Toast(reply.Message, "Error")
		end
	end
	-- Gewinn-Transfer an der Glocke liegt im Depot (WP4) – dort mitschalten
	if batch.AutoTransfer ~= nil then
		ctx.RequestFull("TradeAuto", { On = batch.AutoTransfer == true }, true)
	end
end

local function scheduleSave(key: string)
	pending[key] = deepCopy(current[key])
	saveToken += 1
	local token = saveToken
	setStatus(T("ui.set.saving"), Theme.Muted)
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			flush()
		end
	end)
end

function Settings.Get(): { [string]: any }
	return current
end

-- Wert setzen ("Key" oder "Key.Feld"): geklemmt, sofort wirksam, gebündelt gespeichert
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
	refreshRows()
end

-- flacher Vergleich (Tabellen-Einstellungen wie Indicators haben nur einfache Werte)
local function sameValue(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

-- Server-Stand übernehmen (lokal noch nicht gespeicherte Änderungen bleiben). Der volle State alle 20 s
-- feuert den Hook nur, wenn sich wirklich etwas geändert hat.
local function mergeServer(serverSettings: any)
	if type(serverSettings) ~= "table" then
		return
	end
	local changed = false
	for key, entry in pairs(schema) do
		if pending[key] == nil and serverSettings[key] ~= nil then
			local cleaned = clean(entry, serverSettings[key], current[key])
			if not sameValue(cleaned, current[key]) then
				current[key] = cleaned
				changed = true
			end
		end
	end
	if changed then
		fire()
		refreshRows()
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

local function makeRow(parent: Instance, order: number): (Frame, Frame, TextLabel)
	-- Zeile auf Surface2 mit 1-px-Rahmen: Beschriftung links, Bedienelement rechtsbündig
	local row: Frame = UI.Card({
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = order,
		Parent = parent,
	})
	local label = UI.Label({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, -18, 1, 0),
		Text = "",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		Parent = row,
	})
	local control = UI.Create("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.5, -8, 1, -12),
		BackgroundTransparency = 1,
		Parent = row,
	})
	return row, control, label
end

-- Schalter als Pill (an = Accent, Knopf rechts; aus = Hover-Fläche, Knopf links) + AN/AUS-Text
local function boolRow(parent: Instance, order: number, path: string)
	local _, control, label = makeRow(parent, order)
	local track: TextButton = UI.Create("TextButton", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(52, 28),
		BackgroundColor3 = Theme.Hover,
		AutoButtonColor = false,
		Text = "",
		Parent = control,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", { Color = Theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local knob: Frame = UI.Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local state = UI.Label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -62, 0.5, 0),
		Size = UDim2.new(1, -66, 0, 18),
		Text = "",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 14,
		Parent = control,
	})
	track.Activated:Connect(function()
		local modules = ctx and ctx.Modules
		local sfx = modules and modules.Sfx
		if sfx and type(sfx.Play) == "function" then
			pcall(sfx.Play, "UIClick")
		end
		Settings.Set(path, not (getValue(path) == true))
	end)
	local shownOn: boolean? = nil
	table.insert(rows, {
		Refresh = function()
			label.Text = labelFor(path)
			local on = getValue(path) == true
			state.Text = if on then T("ui.on") else T("ui.off")
			state.TextColor3 = if on then Theme.Text else Theme.Muted
			if shownOn == on then
				return
			end
			local first = shownOn == nil
			shownOn = on
			local color = if on then Theme.Accent else Theme.Hover
			local pos = if on then UDim2.new(1, -24, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
			if first then
				track.BackgroundColor3 = color
				knob.Position = pos
			else
				TweenService:Create(track, SWITCH_INFO, { BackgroundColor3 = color }):Play()
				TweenService:Create(knob, SWITCH_INFO, { Position = pos }):Play()
			end
		end,
	})
end

local function enumRow(parent: Instance, order: number, path: string, entry: any)
	local _, control, label = makeRow(parent, order)
	local options: { any } = entry.Options or {}
	local button = UI.Button({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Variant = "Secondary",
		MaxText = 16,
		Corner = 10,
		Parent = control,
	}, function()
		local value = getValue(path)
		local index = table.find(options, value) or 0
		local nextValue = options[index % math.max(1, #options) + 1]
		if nextValue ~= nil then
			Settings.Set(path, nextValue)
		end
	end)
	table.insert(rows, {
		Refresh = function()
			label.Text = labelFor(path)
			button.SetText("‹  " .. optionText(path, getValue(path)) .. "  ›")
		end,
	})
end

local function numberRow(parent: Instance, order: number, path: string, entry: any)
	local _, control, label = makeRow(parent, order)
	local minV: number = entry.Min or 0
	local maxV: number = entry.Max or 1
	local step: number = entry.Step or ((maxV - minV) / 20)
	local function nudge(direction: number)
		local value = tonumber(getValue(path)) or minV
		Settings.Set(path, value + direction * step)
	end
	UI.Button({
		Size = UDim2.new(0, 34, 1, 0),
		Text = "−",
		Variant = "Ghost",
		MaxText = 22,
		Corner = 10,
		Parent = control,
	}, function()
		nudge(-1)
	end)
	UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 34, 1, 0),
		Text = "+",
		Variant = "Ghost",
		MaxText = 22,
		Corner = 10,
		Parent = control,
	}, function()
		nudge(1)
	end)
	-- Regler-Schiene zum Ziehen (Maus/Touch): Bg2 mit Accent-Füllung, Wert in BuilderMono
	local track: Frame = UI.Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -84, 0, 24),
		BackgroundColor3 = Theme.Bg2,
		Active = true,
		Parent = control,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", { Color = Theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local fill: Frame = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local valueLabel = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Face = "MonoBold",
		TextColor3 = WHITE,
		MaxText = 15,
		Outline = 1,
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
	table.insert(
		rowConns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
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
		end)
	)
	table.insert(
		rowConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == dragging then
				dragging = nil
			end
		end)
	)
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
	qualityLabel = nil
end

local function moduleCall(name: string, fnName: string, ...: any): (boolean, any)
	local module = ctx and ctx.Modules and ctx.Modules[name]
	local fn = module and module[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function qualityText(): string
	local ok, tier = moduleCall("Quality", "Tier")
	local tierName = if ok and type(tier) == "string" then tier else "?"
	return T("ui.set.qualityNow", TOr("ui.opt.Quality." .. tierName, tierName))
end

local function infoText(parent: Instance, text: string, order: number, color: Color3?, height: number?)
	UI.Label({
		Size = UDim2.new(1, 0, 0, height or 56),
		Text = text,
		Face = "Body",
		TextColor3 = color or Theme.Text2,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxText = 15,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function buildContent()
	local win = window
	if not win then
		return
	end
	local content: ScrollingFrame = win.Content
	clearContent(content)
	builtLang = ctx.Lang_()
	win.TitleLabel.Text = UI.Upper(T("ui.settingsTitle"))
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	statusLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = T("ui.set.hint"),
		Face = "Body",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	for _, section in ipairs(SECTIONS) do
		UI.Section(content, T("ui.sec." .. section.Key), nextOrder(), Theme.Accent)
		for _, path in ipairs(section.Items) do
			local entry = entryFor(path)
			if entry then
				if entry.Type == "boolean" then
					boolRow(content, nextOrder(), path)
				elseif entry.Type == "enum" then
					enumRow(content, nextOrder(), path, entry)
				elseif entry.Type == "number" then
					numberRow(content, nextOrder(), path, entry)
				end
			end
		end
		if section.Key == "graphics" then
			qualityLabel = UI.Label({
				Size = UDim2.new(1, 0, 0, 20),
				Text = qualityText(),
				Face = "Body",
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxText = 14,
				LayoutOrder = nextOrder(),
				Parent = content,
			})
			-- Fotomodus für alle (Taste F7; auf dem Handy nur über diesen Knopf, lang drücken beendet)
			local row = UI.Row(content, nextOrder(), 44)
			UI.Button({
				Size = UDim2.new(1, 0, 1, 0),
				Text = T("ui.set.photoMode"),
				Variant = "Secondary",
				MaxText = 16,
				Corner = 10,
				Parent = row,
			}, function()
				ctx.Windows.Close()
				task.delay(0.2, function()
					moduleCall("PhotoMode", "Toggle")
				end)
			end)
		end
	end
	-- Info: Disclaimer (§A2), Regeln + Einspruch, Version
	UI.Section(content, T("ui.sec.info"), nextOrder(), Theme.Muted)
	infoText(content, T("core.disclaimer"), nextOrder(), Theme.Text, 72)
	infoText(content, T("ui.info.rules"), nextOrder(), nil, 72)
	infoText(content, T("ui.info.appeal"), nextOrder(), nil, 56)
	local config = ctx.Config
	infoText(content, T("ui.version", tostring(config and config.Version or "?")), nextOrder(), Theme.Muted, 20)
	refreshRows()
end

local function openWindow()
	if not window then
		window = UI.Window(T("ui.settingsTitle"), WINDOW_W, WINDOW_H, Theme.Accent)
		buildContent()
	elseif builtLang ~= ctx.Lang_() then
		buildContent()
	else
		refreshRows()
		local label = qualityLabel
		if label then
			label.Text = qualityText()
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

-- 1-s-Takt: Sprache gewechselt / Grafikstufe geändert, während das Fenster offen ist
function Settings.Tick()
	local win = window
	if not win or not win.IsOpen then
		return
	end
	if builtLang ~= ctx.Lang_() then
		buildContent()
		return
	end
	local label = qualityLabel
	if label then
		local text = qualityText()
		if label.Text ~= text then
			label.Text = text
		end
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
	-- Menü-Taste (M / Start): offenes Fenster schließen, sonst Einstellungen öffnen
	local controls = ctx.Modules.Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("Menu", function(state)
			if state ~= "Begin" then
				return
			end
			-- im Fotomodus ist alles ausgeblendet: Menü-Taste beendet ihn zuerst
			local ok, photo = moduleCall("PhotoMode", "IsActive")
			if ok and photo == true then
				moduleCall("PhotoMode", "Toggle")
				return
			end
			if ctx.Windows.IsOpen() then
				ctx.Windows.Close()
			else
				ctx.Windows.Open("Settings")
			end
		end)
	end
end

function Settings.Start()
	fire() -- alle Module bekommen die Startwerte
end

return Settings
