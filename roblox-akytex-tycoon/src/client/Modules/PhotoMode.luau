-- =====================================================================
--  AKYTEX TYCOON – Foto-Modus für alle (Client/Modules/PhotoMode)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5, §B11.3 (Fotospots), §D WP2 („Fotomodus für alle,
--  Langdruck beendet auf Touch“). Basis: CC-PhotoMode (REUSE §1.4 COPY, ohne Admin-Sperre).
--
--  Taste F7 (Controls-Aktion "PhotoMode") oder Einstellungen -> Grafik -> Fotomodus (Handy). Rein clientseitig:
--  1,5 s Hinweis-Toast, dann ausblenden: eigene UI (ctx.Gui), Touch-Knöpfe (ctx.TouchGui), Effekt-Ebene,
--  Roblox-Oberfläche (gemerkt und wiederhergestellt) und alle ProximityPrompts (auch wenn der Server sie wieder
--  einschaltet). Nochmal = alles wieder an. Hook "PhotoMode"(on) für andere Ebenen (Banner, Monitore, F8).
--  Handy/Tablet: bei ausgeblendeter UI beendet ein langes Drücken auf den Bildschirm den Modus (REUSE §7 #37).
--
--  Öffentliche API (§C7.5):
--    PhotoMode.Toggle()
--    PhotoMode.IsActive(): boolean
--  Zusätzlich: PhotoMode.Init(ctx), PhotoMode.Start()
-- =====================================================================

local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local PhotoMode = {}

local ctx: any = nil

local DELAY = 1.5 -- Sekunden Toast, bevor ausgeblendet wird
local MAX_PROMPT_SCAN = 20000 -- höchstens so viele Instanzen beim Einschalten durchsuchen (große Stadt)

local photoMode = false
local photoPending = false
local photoToken = 0
local photoHidden: { [ProximityPrompt]: boolean } = {}
local photoConnections: { RBXScriptConnection } = {}
local savedCoreGui: { [Enum.CoreGuiType]: boolean } = {}
local savedGui: { [Instance]: boolean } = {}

local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

-- Modul-Funktion sicher aufrufen (fehlende Module sind kein Fehler)
local function tryCall(name: string, fnName: string, ...: any)
	local modules = ctx and ctx.Modules
	local m = if type(modules) == "table" then modules[name] else nil
	local fn = if type(m) == "table" then m[fnName] else nil
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

local function fireHook(name: string, ...: any)
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.Fire) == "function" then
		hooks.Fire(name, ...)
	end
end

local function setGuiEnabled(gui: any, on: boolean)
	if typeof(gui) ~= "Instance" or not gui:IsA("LayerCollector") then
		return
	end
	if not on then
		savedGui[gui] = gui.Enabled
		gui.Enabled = false
	elseif savedGui[gui] ~= nil then
		gui.Enabled = savedGui[gui] == true
		savedGui[gui] = nil
	end
end

local function hidePrompt(prompt: ProximityPrompt)
	local function off()
		if photoMode and prompt.Enabled then
			photoHidden[prompt] = true
			prompt.Enabled = false
		end
	end
	off()
	-- Der Server schaltet Prompts evtl. wieder ein -> sofort wieder aus
	table.insert(photoConnections, prompt:GetPropertyChangedSignal("Enabled"):Connect(off))
end

local function startPhotoMode()
	photoMode = true
	local ui = ctx and ctx.UI
	if ui and type(ui.CloseAll) == "function" then
		pcall(ui.CloseAll) -- offene Fenster zu
	end
	setGuiEnabled(ctx and ctx.Gui, false)
	setGuiEnabled(ctx and ctx.TouchGui, false)
	tryCall("Effects", "SetHidden", true)
	fireHook("PhotoMode", true)
	-- Roblox-Oberfläche merken und ausblenden
	savedCoreGui = {}
	for _, item in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if item ~= Enum.CoreGuiType.All then
			local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, item)
			-- Nicht lesbar -> beim Beenden trotzdem wieder einschalten (sonst bliebe es für immer aus)
			savedCoreGui[item] = not ok or enabled == true
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	local scanned = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		scanned += 1
		if scanned > MAX_PROMPT_SCAN then
			break
		end
		if inst:IsA("ProximityPrompt") then
			hidePrompt(inst)
		end
	end
	table.insert(
		photoConnections,
		workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("ProximityPrompt") then
				hidePrompt(inst)
			end
		end)
	)
end

local function stopPhotoMode()
	photoMode = false
	for _, connection in ipairs(photoConnections) do
		connection:Disconnect()
	end
	photoConnections = {}
	setGuiEnabled(ctx and ctx.Gui, true)
	setGuiEnabled(ctx and ctx.TouchGui, true)
	table.clear(savedGui)
	tryCall("Effects", "SetHidden", false)
	for item, enabled in pairs(savedCoreGui) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, enabled)
	end
	-- Rucksack/Lebensbalken bleiben im Tycoon immer aus (Main.client)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false)
	for prompt in pairs(photoHidden) do
		if prompt.Parent then
			prompt.Enabled = true
		end
	end
	photoHidden = {}
	fireHook("PhotoMode", false)
end

function PhotoMode.IsActive(): boolean
	return photoMode
end

local function keyName(): string
	local keys = ctx and ctx.Config and ctx.Config.Client and ctx.Config.Client.Keys
	local list = keys and keys.PhotoMode
	if type(list) == "table" and type(list[1]) == "string" then
		return list[1]
	end
	return "F7"
end

function PhotoMode.Toggle()
	if photoMode or photoPending then
		photoToken += 1
		photoPending = false
		if photoMode then
			stopPhotoMode()
			if ctx and type(ctx.Toast) == "function" then
				ctx.Toast(T("ui.photo.off"), "Info")
			end
		end
		return
	end
	photoPending = true
	photoToken += 1
	local token = photoToken
	if ctx and type(ctx.Toast) == "function" then
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		ctx.Toast(if touchOnly then T("ui.photo.onTouch") else T("ui.photo.on", keyName()), "Info")
	end
	task.delay(DELAY, function()
		if photoPending and photoToken == token then
			photoPending = false
			startPhotoMode()
		end
	end)
end

function PhotoMode.Init(context: any)
	ctx = context
	-- Taste über Controls (Aktion "PhotoMode", in jedem Kontext erlaubt – auch bei versteckter UI)
	local controls = ctx.Modules and ctx.Modules.Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("PhotoMode", function(state)
			if state == "Begin" then
				PhotoMode.Toggle()
			end
		end)
	end
end

function PhotoMode.Start()
	-- Handy: die eigene UI ist im Foto-Modus aus -> lang drücken = beenden
	UserInputService.TouchLongPress:Connect(function(_positions, state: Enum.UserInputState)
		if photoMode and state == Enum.UserInputState.Begin then
			PhotoMode.Toggle()
		end
	end)
end

return PhotoMode
