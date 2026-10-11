-- =====================================================================
--  CLUTCH CLASH – Client-Start (src/client/Main.client.luau)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.1–C7.3, REUSE §10 (Meteor-Heist-Skelett).
--
--  Dieses Skript baut die Oberfläche (ScreenGui + unskalierte TouchGui), den gemeinsamen
--  "Rucksack" ctx für alle Client-Module, den Request-Wrapper, den State-Merge und leitet alle
--  Server-Nachrichten als Hooks weiter. Danach startet es die Module in fester Reihenfolge:
--  jedes Init(ctx) in pcall, danach jedes Start() in pcall – fehlt ein Modul (anderes Paket noch
--  nicht fertig), gibt es nur ein warn und alles andere läuft weiter.
--  Admin-Module nur, wenn der Server das Attribut IsAdmin = true setzt.
--
--  ctx (C7.1): Player, Config, Lang, Util, Net, Types, Remotes, Gui, TouchGui, State, StateTime,
--    Request(action, arg?) -> Antwort bei Ok, sonst nil (Toast bei Message / keine Antwort)
--    RequestFull(action, arg?, silent?) -> { Ok, Message?, ... } (immer eine Tabelle)
--    Toast(text, kind?), T(key, ...), Lang_() -> "de" | "en", Hooks, Windows, UI, Modules
--  Hooks, die Main.client feuert: "State"(state, changed), "Notify"(text, kind), "Match:<Kind>"(data),
--    "Combat:<Op>"(data), "Effect:<Name>"(strength, data), "Armed"(info), "Disarmed"(),
--    "LocalPopped"(recap?), "LocalRevived"(), "World"(world, slot?), "Balance"(version).
--  Ein PreRender-Loop für alle Effekte (Frame(dt) der WP10-Module) + 1-s-Takt (Tick()) in pcall.
-- =====================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Lang = require(Shared:WaitForChild("Lang")) :: any
local Util = require(Shared:WaitForChild("Util")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Types = require(Shared:WaitForChild("Types")) :: any

local ModulesFolder = script.Parent:WaitForChild("Modules")

-- Startreihenfolge (C7.1) – fehlende Module werden übersprungen
local MODULE_ORDER = {
	"UI",
	"Hooks",
	"Sfx",
	"Effects",
	"Highlights",
	"CombatFX",
	"Controls",
	"TouchControls",
	"Hud",
	"CombatHud",
	"Settings",
	"ArenaLook",
	"FpsCamera",
	"AimAssist",
	"Viewmodel",
	"Movement",
	"Replication",
	"WeaponClient",
	"QueueUI",
	"MatchUI",
	"Spectate",
	"Scoreboard",
	"Tutorial",
	"BotAnimator",
	"Training",
	"Progress",
	"ChatClient",
	"Shop",
	"Locker",
	"CrateReveal",
	"Finishers",
}
local ADMIN_MODULES = { "AdminPanel", "AdminTools", "Fly", "PhotoMode", "DebugOverlay" }
-- Nur diese (eigenen) Module bekommen Frame(dt)/Tick() aus den zentralen Schleifen
local FRAME_MODULES = { "UI", "Effects", "CombatFX", "CombatHud", "TouchControls", "Settings" }
local TICK_MODULES = { "Hud", "CombatHud", "Settings" }

local ERROR_LOG_GAP = 10 -- Fehler derselben Quelle höchstens alle 10 s loggen
local GETFULL_AFTER = 5 -- Sekunden ohne State -> einmal "GetFull" anfragen

-- ---------------------------------------------------------------------
-- MODULE LADEN (require in pcall)
-- ---------------------------------------------------------------------
local loaded: { [string]: any } = {}
local function load(name: string): any?
	if loaded[name] ~= nil then
		return loaded[name] or nil
	end
	local moduleScript = ModulesFolder:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		loaded[name] = false
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" then
		warn(("[Client] Modul %s konnte nicht geladen werden: %s"):format(name, tostring(result)))
		loaded[name] = false
		return nil
	end
	loaded[name] = result
	return result
end

local UI = load("UI")
local Hooks = load("Hooks")
assert(UI and Hooks, "[Client] UI und Hooks werden gebraucht")

-- ---------------------------------------------------------------------
-- GRUNDGERÜST: Oberfläche (mit UIScale) + unskalierte Touch-Ebene
-- ---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ClutchClashUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false
gui.DisplayOrder = 1
gui.Parent = playerGui

-- Touch-Knöpfe: eigene ScreenGui OHNE UIScale (sonst schrumpfen sie unter 64 px), nichts unter der Notch
local touchGui = Instance.new("ScreenGui")
touchGui.Name = "ClutchClashTouch"
touchGui.ResetOnSpawn = false
touchGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
touchGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
touchGui.DisplayOrder = 3
touchGui.Parent = playerGui

-- Gemeinsamer "Rucksack" für alle Module (C7.1)
local ctx: { [string]: any } = {
	Player = player,
	Config = Config,
	Lang = Lang,
	Util = Util,
	Net = Net,
	Types = Types,
	Remotes = {},
	Gui = gui,
	TouchGui = touchGui,
	State = {},
	StateTime = 0,
	Hooks = Hooks,
	UI = UI,
	Windows = UI.Windows,
	Modules = { UI = UI, Hooks = Hooks },
}

-- Aktuelle Sprache: Einstellung "de"/"en", sonst LocaleId des Spielers
function ctx.Lang_(): "de" | "en"
	local settings: any = nil
	local settingsModule = ctx.Modules.Settings
	if settingsModule and type(settingsModule.Get) == "function" then
		local ok, value = pcall(settingsModule.Get)
		if ok then
			settings = value
		end
	end
	if type(settings) ~= "table" then
		settings = ctx.State.Settings
	end
	local choice = type(settings) == "table" and settings.Lang or nil
	if choice == "de" or choice == "en" then
		return choice
	end
	local ok, lang = pcall(Lang.For, player, nil)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return "en"
end

function ctx.T(key: string, ...: any): string
	return Lang.T(ctx.Lang_(), key, ...)
end

function ctx.Toast(text: string, kind: string?)
	UI.Toast(text, kind)
end

-- ---------------------------------------------------------------------
-- ANFRAGEN AN DEN SERVER (MH-Muster: pcall um InvokeServer, Toast bei Message)
-- ---------------------------------------------------------------------
function ctx.RequestFull(action: string, arg: any?, silent: boolean?): { [string]: any }
	local remote = ctx.Remotes.Request
	if not remote or not remote:IsA("RemoteFunction") then
		if not silent then
			UI.Toast(ctx.T("core.noAnswer"), "Error")
		end
		return { Ok = false, Message = ctx.T("core.noAnswer") }
	end
	local ok, result = pcall(function()
		return (remote :: RemoteFunction):InvokeServer(action, arg)
	end)
	if ok and type(result) == "table" then
		if not silent and type(result.Message) == "string" and result.Message ~= "" then
			UI.Toast(result.Message, if result.Ok then "Success" else "Error")
		end
		result.Ok = result.Ok == true
		return result
	end
	if not silent then
		UI.Toast(ctx.T("core.noAnswer"), "Error")
	end
	return { Ok = false, Message = ctx.T("core.noAnswer") }
end

-- Kurzform: Antwort-Tabelle bei Erfolg, sonst nil (Meldung kam schon als Toast)
function ctx.Request(action: string, arg: any?): any
	local reply = ctx.RequestFull(action, arg)
	if reply.Ok then
		return reply
	end
	return nil
end

-- ---------------------------------------------------------------------
-- MODULE STARTEN (Init alle, dann Start alle – jeweils in pcall)
-- ---------------------------------------------------------------------
local function safeCall(label: string, fn: any, ...: any): boolean
	if type(fn) ~= "function" then
		return true
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[Client] %s fehlgeschlagen: %s"):format(label, tostring(err)))
	end
	return ok
end

local function startModules(names: { string })
	local ready: { { Name: string, Module: any } } = {}
	for _, name in ipairs(names) do
		local module = load(name)
		if module then
			ctx.Modules[name] = module
			table.insert(ready, { Name = name, Module = module })
		else
			warn("[Client] Modul fehlt (übersprungen): " .. name)
		end
	end
	for _, entry in ipairs(ready) do
		if not safeCall(entry.Name .. ".Init", entry.Module.Init, ctx) then
			entry.Module = nil
		end
	end
	for _, entry in ipairs(ready) do
		if entry.Module then
			safeCall(entry.Name .. ".Start", entry.Module.Start)
		end
	end
end

-- ---------------------------------------------------------------------
-- REMOTES + WELT-ZUSTAND
-- ---------------------------------------------------------------------
local myCombatId: number = player.UserId
local armed: { [string]: any }? = nil
local inMatch = false
local popped = false

local function fireWorld(world: string, slot: number?)
	Hooks.Fire("World", world, slot)
end

local function setPopped(recap: any?)
	if popped then
		return
	end
	popped = true
	Hooks.Fire("LocalPopped", recap)
end

local function setRevived()
	if not popped then
		return
	end
	popped = false
	Hooks.Fire("LocalRevived")
end

-- State: Sticky-Merge (fehlende Schlüssel bleiben – auch beim vollen State alle 20 s), changed = Liste + Set
local function onState(partial: any, _full: any)
	if type(partial) ~= "table" then
		return
	end
	local state = ctx.State
	local changed: { [any]: any } = {}
	for key, value in pairs(partial) do
		if type(key) == "string" then
			state[key] = value
			table.insert(changed, key)
			changed[key] = true
		end
	end
	ctx.StateTime = os.clock()
	Hooks.Fire("State", state, changed)
end

local function onMatch(kind: any, data: any)
	if type(kind) ~= "string" then
		return
	end
	if type(data) ~= "table" then
		data = {}
	end
	if kind == "Start" then
		inMatch = true
		local slot = tonumber(data.Slot) or 0
		if slot == 0 or data.Mode == "Crown" then
			fireWorld("Crown", 0)
		else
			fireWorld("Match", slot)
		end
	elseif kind == "Elim" then
		if tonumber(data.V) == myCombatId then
			setPopped(nil)
		end
	elseif kind == "Recap" then
		-- Rückblick kommt nach dem Pop: falls das Elim fehlte, gilt man jetzt als gepoppt
		setPopped(data)
	end
	Hooks.Fire("Match:" .. kind, data)
	if kind == "Closed" then
		inMatch = false
		if popped then
			popped = false
		end
		if not armed then
			fireWorld("Lobby", nil)
		end
	end
end

local function onCombat(op: any, data: any)
	if type(op) ~= "string" then
		return
	end
	if type(data) ~= "table" then
		data = {}
	end
	if op == "Armed" then
		armed = data
		myCombatId = tonumber(data.Id) or player.UserId
		setRevived()
		Hooks.Fire("Combat:Armed", data)
		Hooks.Fire("Armed", data)
		if data.Ctx == "Range" then
			fireWorld("Range", nil)
		end
		return
	elseif op == "Disarmed" then
		armed = nil
		popped = false
		Hooks.Fire("Combat:Disarmed", data)
		Hooks.Fire("Disarmed")
		if not inMatch then
			fireWorld("Lobby", nil)
		end
		return
	end
	Hooks.Fire("Combat:" .. op, data)
end

-- Eigener Character: Attribut "Alive" (CombatService) als zweite Quelle für Pop/Revive
local aliveConn: RBXScriptConnection? = nil
local function watchCharacter(character: Model)
	if aliveConn then
		aliveConn:Disconnect()
		aliveConn = nil
	end
	aliveConn = character:GetAttributeChangedSignal("Alive"):Connect(function()
		if not armed then
			return
		end
		local alive = character:GetAttribute("Alive")
		if alive == false then
			setPopped(nil)
		elseif alive == true then
			setRevived()
		end
	end)
end

-- Erst NACH dem Modul-Start verbinden: bis dahin hält Roblox die Pakete in der Warteschlange,
-- so verpasst kein Modul den ersten vollen State oder ein frühes "Armed".
local function connectRemotes()
	local remotes = ctx.Remotes
	local function event(name: string): RemoteEvent?
		local remote = remotes[name]
		if remote and remote:IsA("RemoteEvent") then
			return remote
		end
		warn("[Client] Remote fehlt: " .. name)
		return nil
	end
	local stateRemote = event("State")
	if stateRemote then
		stateRemote.OnClientEvent:Connect(onState)
	end
	local notify = event("Notify")
	if notify then
		notify.OnClientEvent:Connect(function(text, kind)
			if type(text) ~= "string" then
				return
			end
			local k = if type(kind) == "string" then kind else "Info"
			UI.Toast(text, k)
			Hooks.Fire("Notify", text, k)
		end)
	end
	local effect = event("Effect")
	if effect then
		effect.OnClientEvent:Connect(function(name, strength, data)
			if type(name) ~= "string" then
				return
			end
			local amount = if type(strength) == "number" and strength == strength then strength else 0
			local effects = ctx.Modules.Effects
			if effects and type(effects.Play) == "function" then
				safeCall("Effects.Play(" .. name .. ")", effects.Play, name, amount, data)
			end
			Hooks.Fire("Effect:" .. name, amount, data)
		end)
	end
	local match = event("Match")
	if match then
		match.OnClientEvent:Connect(onMatch)
	end
	local combat = event("Combat")
	if combat then
		combat.OnClientEvent:Connect(onCombat)
	end
end

-- ---------------------------------------------------------------------
-- LIVE-BALANCE: ReplicatedStorage.LiveBalance (StringValue mit JSON) -> Config.ApplyBalance
-- ---------------------------------------------------------------------
local lastBalance = ""
local function applyBalance(value: StringValue)
	local text = value.Value
	if type(text) ~= "string" or text == "" or text == lastBalance then
		return
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or type(data) ~= "table" then
		warn("[Client] LiveBalance: kein gültiges JSON")
		return
	end
	lastBalance = text
	if safeCall("Config.ApplyBalance", Config.ApplyBalance, data) then
		Hooks.Fire("Balance", tonumber(data.Version) or 0)
	end
end

local balanceConn: RBXScriptConnection? = nil
local function watchBalance(child: Instance)
	if child.Name ~= "LiveBalance" or not child:IsA("StringValue") then
		return
	end
	if balanceConn then
		balanceConn:Disconnect()
	end
	local value = child :: StringValue
	balanceConn = value.Changed:Connect(function()
		applyBalance(value)
	end)
	applyBalance(value)
end

-- ---------------------------------------------------------------------
-- ADMIN-MODULE (nur wenn der Server dich als Admin markiert; Server prüft trotzdem jede Aktion)
-- ---------------------------------------------------------------------
local adminStarted = false
local function checkAdmin()
	if adminStarted or player:GetAttribute("IsAdmin") ~= true then
		return
	end
	adminStarted = true
	startModules(ADMIN_MODULES)
end

-- ---------------------------------------------------------------------
-- SCHLEIFEN: ein PreRender für alle Effekte + 1-s-Takt
-- ---------------------------------------------------------------------
local lastLoopError: { [string]: number } = {}
local function loopCall(label: string, fn: any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		local now = os.clock()
		if now - (lastLoopError[label] or -math.huge) >= ERROR_LOG_GAP then
			lastLoopError[label] = now
			warn(("[Client] %s: %s"):format(label, tostring(err)))
		end
	end
end

local frameFns: { { Label: string, Fn: (number) -> () } } = {}
local tickFns: { { Label: string, Fn: () -> () } } = {}
local function collectLoops()
	for _, name in ipairs(FRAME_MODULES) do
		local module = ctx.Modules[name]
		if module and type(module.Frame) == "function" then
			table.insert(frameFns, { Label = name .. ".Frame", Fn = module.Frame })
		end
	end
	for _, name in ipairs(TICK_MODULES) do
		local module = ctx.Modules[name]
		if module and type(module.Tick) == "function" then
			table.insert(tickFns, { Label = name .. ".Tick", Fn = module.Tick })
		end
	end
end

-- ---------------------------------------------------------------------
-- LOS GEHT'S
-- ---------------------------------------------------------------------
-- Roblox-Rucksack und Lebensbalken aus (wir haben eigene); mit Wiederholung, falls CoreGui noch lädt
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- UI zuerst (braucht ctx für Hooks/Sounds), dann alle anderen in fester Reihenfolge
UI.Init(ctx)
ctx.Remotes = Net.GetRemotes() -- Module brauchen die Remotes schon im Init (FX, Look, …)
startModules(MODULE_ORDER)
collectLoops()
fireWorld("Lobby", nil) -- Start-Welt (vor den ersten Server-Paketen)
connectRemotes()

RunService.PreRender:Connect(function(dt: number)
	for _, entry in ipairs(frameFns) do
		loopCall(entry.Label, entry.Fn, dt)
	end
end)

task.spawn(function()
	while true do
		-- Ein Fehler darf die Schleife nicht für immer anhalten
		for _, entry in ipairs(tickFns) do
			loopCall(entry.Label, entry.Fn)
		end
		task.wait(1)
	end
end)

-- Admin
player:GetAttributeChangedSignal("IsAdmin"):Connect(checkAdmin)
checkAdmin()

-- Eigener Character (Pop/Revive über Attribut "Alive")
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

-- Live-Balance (StringValue kann auch später erst erscheinen)
ReplicatedStorage.ChildAdded:Connect(watchBalance)
local existingBalance = ReplicatedStorage:FindFirstChild("LiveBalance")
if existingBalance then
	watchBalance(existingBalance)
end

-- Kam nach ein paar Sekunden noch kein State (sehr langsamer Join), einmal voll nachfragen
task.delay(GETFULL_AFTER, function()
	if ctx.StateTime == 0 then
		local reply = ctx.RequestFull("GetFull", nil, true)
		if reply.Ok and type(reply.State) == "table" then
			onState(reply.State, true)
		end
	end
end)

-- Willkommen (lokalisiert, mit der passenden Taste für das Gerät)
task.delay(2, function()
	UI.Toast(ctx.T("ui.welcome", tostring(Config.GameName)), "Event")
	local controls = ctx.Modules.Controls
	local kind = if controls and type(controls.Input) == "function" then controls.Input() else "KBM"
	local hintKey = if kind == "Touch"
		then "ui.welcomeTouch"
		elseif kind == "Gamepad" then "ui.welcomePad"
		else "ui.welcomeKbm"
	task.delay(3.5, function()
		UI.Toast(ctx.T(hintKey), "Info")
	end)
end)
