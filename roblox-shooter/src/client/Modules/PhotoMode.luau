-- =====================================================================
--  CLUTCH CLASH – Foto-Modus für Thumbnails (Client/Modules/PhotoMode)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Basis: Meteor-Heist-PhotoMode (REUSE §1.4, COPY + Shooter-Teile).
--  Nur für den Besitzer (Modul lädt nur bei IsAdmin). Taste H (Config.Client.Keys.PhotoMode, falls gesetzt) oder
--  Admin-Panel -> Kräfte -> Foto-Modus. Rein clientseitig: 1.5 s Toast, dann ausblenden:
--  eigene UI (ctx.Gui), Touch-Knöpfe (ctx.TouchGui), Viewmodel, Fadenkreuz (CombatHud), Effekte (Ansagen/Zahlen),
--  Roblox-Oberfläche (gemerkt und wiederhergestellt) und alle ProximityPrompts (auch wenn der Server sie wieder
--  einschaltet). Nochmal = alles wieder an. Hook "PhotoMode"(on) für Admin-Anzeigen (ESP, F8).
--  Handy/Tablet: ohne Tastatur und bei ausgeblendeter UI beendet ein langes Drücken auf den Bildschirm den Modus.
--
--  Öffentliche API (C7.4):
--    PhotoMode.Toggle()
--    PhotoMode.IsActive(): boolean
--    PhotoMode.Init(ctx) / PhotoMode.Start()
-- =====================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local PhotoMode = {}

local player = Players.LocalPlayer
local ctx: any = nil

local DELAY = 1.5 -- Sekunden Toast, bevor ausgeblendet wird

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

local function module(name: string): any
	local modules = ctx and ctx.Modules
	return if type(modules) == "table" then modules[name] else nil
end

-- Modul-Funktion sicher aufrufen (fehlende Module sind kein Fehler)
local function tryCall(name: string, fnName: string, ...: any)
	local m = module(name)
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
	tryCall("Viewmodel", "SetHidden", true)
	tryCall("CombatHud", "Show", false)
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
	for _, inst in ipairs(workspace:GetDescendants()) do
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
	tryCall("Viewmodel", "SetHidden", false)
	local weapon = module("WeaponClient")
	local armed = false
	if weapon and type(weapon.IsArmed) == "function" then
		local ok, result = pcall(weapon.IsArmed)
		armed = ok and result == true
	end
	if armed then
		tryCall("CombatHud", "Show", true)
	end
	for item, enabled in pairs(savedCoreGui) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, enabled)
	end
	-- Backpack/Health bleiben im Shooter immer aus (WP10)
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
	return "H"
end

function PhotoMode.Toggle()
	if photoMode or photoPending then
		photoToken += 1
		photoPending = false
		if photoMode then
			stopPhotoMode()
			if ctx and type(ctx.Toast) == "function" then
				ctx.Toast(T("admin.photoOff"), "Info")
			end
		end
		return
	end
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	photoPending = true
	photoToken += 1
	local token = photoToken
	if ctx and type(ctx.Toast) == "function" then
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		ctx.Toast(if touchOnly then T("admin.photoOnTouch") else T("admin.photoOn", keyName()), "Info")
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
end

function PhotoMode.Start()
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[keyName()]
	end)
	local key: EnumItem = if ok and typeof(code) == "EnumItem" then code else Enum.KeyCode.H
	-- Funktioniert auch bei versteckter UI, aber nicht beim Tippen in einer TextBox
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= key or UserInputService:GetFocusedTextBox() then
			return
		end
		PhotoMode.Toggle()
	end)
	-- Handy: die eigene UI (auch der Admin-Knopf) ist im Foto-Modus aus -> lang drücken = beenden
	UserInputService.TouchLongPress:Connect(function(_positions, state: Enum.UserInputState)
		if photoMode and state == Enum.UserInputState.Begin then
			PhotoMode.Toggle()
		end
	end)
end

return PhotoMode
