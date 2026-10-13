-- =====================================================================
--  AKYTEX TYCOON – Client-Start (src/client/Main.client.luau)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.1–§C7.4, §C8. Basis: CC-Main.client (REUSE §1.4 ADAPT).
--
--  Baut die Oberfläche (ScreenGui "AkytexTycoonUI" mit UIScale + unskalierte "AkytexTycoonTouch"), den gemeinsamen
--  "Rucksack" ctx, den Request-Wrapper und den State-Merge. Startet die Module in fester Reihenfolge (§C7.1):
--  alle Init(ctx) in pcall (fehlgeschlagene Module werden entfernt – kein Start/Frame/Tick, für andere "fehlt"),
--  danach alle Start() in pcall, ERST DANN die Remotes verbinden (Roblox hält Pakete bis dahin zurück – kein Modul
--  verpasst den ersten vollen State). Admin-Module nur, wenn der Server das Attribut IsAdmin = true setzt.
--
--  ctx (§C7.1): Player, Config, Lang, Util, Net, Types, Format, Clock, Remotes, Gui, TouchGui, State, StateTime,
--    Request(action, arg?) -> Antwort bei Ok, sonst nil (Toast bei Message / keine Antwort)
--    RequestFull(action, arg?, silent?) -> { Ok, Message?, ... } (immer eine Tabelle)
--    Toast(text, kind?), T(key, ...), Lang_() -> "de" | "en", Hooks, Windows, UI, Modules
--    + Fps (gemessene Bildrate, aktualisiert alle 0,5 s im einen PreRender-Loop)
--  Hooks, die Main.client feuert (§C7.2): "State"(state, changed) · "Notify"(text, kind) · "Effect:<Name>"(strength, data)
--    (nach Effects.Play) · "Market:<Kind>"(data) · "World:<Kind>"(data) · "Replay"(tick, close, phase) nur falls
--    MarketClient ihn nicht selbst gefeuert hat (genau einmal je Paket).
--  Ein PreRender-Loop für FRAME_MODULES (Frame(dt)) + 1-s-Takt für TICK_MODULES (Tick()), jeweils in pcall.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Lang = require(Shared:WaitForChild("Lang")) :: any
local Util = require(Shared:WaitForChild("Util")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Types = require(Shared:WaitForChild("Types")) :: any
local Format = require(Shared:WaitForChild("Format")) :: any
local Clock = require(Shared:WaitForChild("Clock")) :: any

local ModulesFolder = script.Parent:WaitForChild("Modules")

-- Startreihenfolge (§C7.1) – fehlende Module (Paket noch nicht fertig) werden übersprungen
local MODULE_ORDER = {
	"UI",
	"Hooks",
	"Sfx",
	"Effects",
	"Highlights",
	"Controls",
	"TouchControls",
	"Quality",
	"Hud",
	"Settings",
	"PhotoMode",
	"MarketClient",
	"ChartView",
	"Ticker",
	"Monitors",
	"NewsFeed",
	"Terminal",
	"DepotView",
	"EffectsMarket",
	"WorldLook",
	"CityLife",
	"Vehicles",
	"Garage",
	"TowerView",
	"TowerUI",
	"Elevator",
	"WelcomeBack",
	"Boutique",
	"EffectsTower",
	"Tutorial",
	"Academy",
	"Quests",
	"Season",
	"Boards",
	"Social",
	"Prestige",
	"Shop",
	"EventsClient",
	"EffectsEvent",
}
-- Bibliotheken: nur Init (kein Start, kein Frame/Tick) – ChartView-Instanzen steuern Terminal/Monitors
local LIBRARY_MODULES: { [string]: boolean } = { ChartView = true }
local ADMIN_MODULES = { "AdminPanel", "AdminTools", "Fly", "DebugOverlay" }
-- Nur diese Module bekommen Frame(dt)/Tick() aus den zentralen Schleifen (§C7.1)
local FRAME_MODULES = {
	"UI",
	"Effects",
	"Terminal",
	"Monitors",
	"Ticker",
	"CityLife",
	"WorldLook",
	"TowerView",
	"Vehicles",
	"EventsClient",
}
local TICK_MODULES = { "Hud", "Settings", "Quests", "NewsFeed", "Tutorial", "Garage", "Season", "Prestige", "Quality" }
-- Server-Ereignisse der Remotes "Market"/"World" (§C8) -> Hooks "Market:<Kind>"/"World:<Kind>"
local MARKET_KINDS: { [string]: boolean } = {
	News = true,
	Event = true,
	Halt = true,
	Bell = true,
	Ipo = true,
	Calendar = true,
	DayClose = true,
}
local WORLD_KINDS: { [string]: boolean } = {
	Pickups = true,
	PickupGone = true,
	Event = true,
	Bear = true,
	Parade = true,
}

local ERROR_LOG_GAP = 10 -- Fehler derselben Quelle höchstens alle 10 s loggen
local GETFULL_AFTER = 5 -- Sekunden ohne State -> einmal "GetFull" anfragen
local FPS_WINDOW = 0.5 -- Bildrate über so viele Sekunden mitteln
local MAX_FRAME_DT = 0.25 -- längere Pausen (Laden, Fenster minimiert) nicht in Frame-Module schieben

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
gui.Name = "AkytexTycoonUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 1
gui.Parent = playerGui

-- Touch-Knöpfe: eigene ScreenGui OHNE UIScale (sonst schrumpfen sie unter 64 px), nichts unter der Notch
local touchGui = Instance.new("ScreenGui")
touchGui.Name = "AkytexTycoonTouch"
touchGui.ResetOnSpawn = false
touchGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
touchGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
touchGui.DisplayOrder = 3
touchGui.Parent = playerGui

-- Gemeinsamer "Rucksack" für alle Module (§C7.1)
local ctx: { [string]: any } = {
	Player = player,
	Config = Config,
	Lang = Lang,
	Util = Util,
	Net = Net,
	Types = Types,
	Format = Format,
	Clock = Clock,
	Remotes = {},
	Gui = gui,
	TouchGui = touchGui,
	State = {},
	StateTime = 0,
	Hooks = Hooks,
	UI = UI,
	Windows = UI.Windows,
	Modules = { UI = UI, Hooks = Hooks },
	Fps = 60,
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
-- ANFRAGEN AN DEN SERVER (pcall um InvokeServer, Toast bei Message)
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

local started: { [string]: boolean } = {}
local function startModules(names: { string })
	local ready: { { Name: string, Module: any } } = {}
	for _, name in ipairs(names) do
		if not started[name] then
			local module = load(name)
			if module then
				ctx.Modules[name] = module
				table.insert(ready, { Name = name, Module = module })
			else
				warn("[Client] Modul fehlt (übersprungen): " .. name)
			end
		end
	end
	for _, entry in ipairs(ready) do
		if not safeCall(entry.Name .. ".Init", entry.Module.Init, ctx) then
			-- halb gebautes Modul nicht weiter benutzen: kein Start, kein Frame/Tick, für andere "fehlt" (REUSE §7 #3)
			entry.Module = nil
			ctx.Modules[entry.Name] = nil
		end
	end
	for _, entry in ipairs(ready) do
		if entry.Module then
			started[entry.Name] = true
			if not LIBRARY_MODULES[entry.Name] then
				safeCall(entry.Name .. ".Start", entry.Module.Start)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- STATE + REMOTES
-- ---------------------------------------------------------------------
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

-- Replay (Tutorial-ACAD, §C7.2): MarketClient feuert "Replay" selbst; Main nur als Rückfall – genau einmal je Paket
local lastReplayFired: number? = nil
local replayDecoder: any = nil
local function decodeReplay(payload: any): (number?, number?, number?)
	if typeof(payload) ~= "buffer" then
		return nil, nil, nil
	end
	if replayDecoder == nil then
		replayDecoder = false
		local folder = Shared:FindFirstChild("Market")
		local codec = folder and folder:FindFirstChild("QuoteCodec")
		if codec and codec:IsA("ModuleScript") then
			local ok, result = pcall(require, codec)
			if ok and type(result) == "table" and type(result.DecodeReplay) == "function" then
				replayDecoder = result
			end
		end
	end
	if not replayDecoder then
		return nil, nil, nil
	end
	local ok, tick, close, phase = pcall(replayDecoder.DecodeReplay, payload)
	if ok and type(tick) == "number" then
		return tick, close, phase
	end
	return nil, nil, nil
end

-- Erst NACH dem Modul-Start verbinden: bis dahin hält Roblox die Pakete in der Warteschlange.
-- Fehlt ein Remote (Server sehr langsam), wird später erneut gesucht – jede Verbindung genau einmal.
local REMOTE_RETRIES = 6
local REMOTE_RETRY_GAP = 5
local connectedRemotes: { [string]: boolean } = {}

local remoteHandlers: { [string]: (...any) -> () } = {
	State = onState,
	Notify = function(text, kind)
		if type(text) ~= "string" then
			return
		end
		local k = if type(kind) == "string" then kind else "Info"
		local message = string.sub(text, 1, 500)
		UI.Toast(message, k)
		Hooks.Fire("Notify", message, k)
	end,
	Effect = function(name, strength, data)
		if type(name) ~= "string" or #name > 40 then
			return
		end
		local amount = if type(strength) == "number" and strength == strength then strength else 0
		local effects = ctx.Modules.Effects
		if effects and type(effects.Play) == "function" then
			safeCall("Effects.Play(" .. name .. ")", effects.Play, name, amount, data)
		end
		Hooks.Fire("Effect:" .. name, amount, data)
	end,
	Market = function(kind, data)
		if type(kind) ~= "string" or not MARKET_KINDS[kind] then
			return
		end
		Hooks.Fire("Market:" .. kind, data)
	end,
	World = function(kind, data)
		if type(kind) ~= "string" or not WORLD_KINDS[kind] then
			return
		end
		Hooks.Fire("World:" .. kind, data)
	end,
	Replay = function(payload)
		local tick, close, phase = decodeReplay(payload)
		if not tick then
			return
		end
		-- alle anderen Verbindungen (MarketClient) laufen synchron vor dem defer; hat jemand dieses Paket
		-- schon als Hook gefeuert, nicht doppelt feuern
		task.defer(function()
			if lastReplayFired ~= tick then
				Hooks.Fire("Replay", tick, close, phase)
			end
		end)
	end,
}
local REMOTE_ORDER = { "State", "Notify", "Effect", "Market", "World", "Replay" }

-- verbindet alle vorhandenen Remotes; true = alles verbunden
local function connectRemotes(): boolean
	local complete = true
	for _, name in ipairs(REMOTE_ORDER) do
		if not connectedRemotes[name] then
			local remote = ctx.Remotes[name]
			if remote and remote:IsA("RemoteEvent") then
				connectedRemotes[name] = true
				remote.OnClientEvent:Connect(remoteHandlers[name])
			else
				complete = false
			end
		end
	end
	return complete
end

local function connectWithRetry()
	if connectRemotes() then
		return
	end
	task.spawn(function()
		for _ = 1, REMOTE_RETRIES do
			task.wait(REMOTE_RETRY_GAP)
			local ok, remotes = pcall(Net.GetRemotes)
			if ok and type(remotes) == "table" then
				for name, remote in pairs(remotes) do
					ctx.Remotes[name] = remote
				end
			end
			if connectRemotes() then
				return
			end
		end
		warn("[Client] Remotes fehlen weiterhin – Server-Nachrichten kommen nicht an")
	end)
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
-- SCHLEIFEN: ein PreRender für alle Frame-Module + 1-s-Takt (beides im selben Loop, kein zweiter Thread)
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
	table.clear(frameFns)
	table.clear(tickFns)
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

local fpsAccum = 0
local fpsFrames = 0
local tickAccum = 0
local focused = true
local function onPreRender(rawDt: number)
	local dt = math.clamp(rawDt, 0, MAX_FRAME_DT)
	-- Bildrate (nur mit Fokus – minimierte Fenster würden die Grafik-Automatik täuschen)
	if focused and rawDt > 0 then
		fpsAccum += rawDt
		fpsFrames += 1
		if fpsAccum >= FPS_WINDOW then
			ctx.Fps = fpsFrames / fpsAccum
			fpsAccum = 0
			fpsFrames = 0
		end
	end
	for _, entry in ipairs(frameFns) do
		loopCall(entry.Label, entry.Fn, dt)
	end
	tickAccum += rawDt
	if tickAccum >= 1 then
		-- nach langen Pausen nicht mehrfach nachholen
		tickAccum = if tickAccum >= 2 then 0 else tickAccum - 1
		for _, entry in ipairs(tickFns) do
			loopCall(entry.Label, entry.Fn)
		end
	end
end

-- ---------------------------------------------------------------------
-- LOS GEHT'S
-- ---------------------------------------------------------------------
-- Roblox-Rucksack und Lebensbalken aus (der Tycoon braucht keine); mit Wiederholung, falls CoreGui noch lädt
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
ctx.Remotes = Net.GetRemotes() -- Module brauchen die Remotes evtl. schon im Init (MarketClient, Terminal)
startModules(MODULE_ORDER)
collectLoops()
Hooks.On("Replay", function(tick)
	if type(tick) == "number" then
		lastReplayFired = tick
	end
end)
connectWithRetry()

UserInputService.WindowFocused:Connect(function()
	focused = true
	fpsAccum, fpsFrames = 0, 0
end)
UserInputService.WindowFocusReleased:Connect(function()
	focused = false
end)
RunService.PreRender:Connect(onPreRender)

-- Admin (Attribut kann auch später kommen)
player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
	checkAdmin()
	collectLoops()
end)
checkAdmin()
collectLoops()

-- Kam nach ein paar Sekunden noch kein State (sehr langsamer Join), einmal voll nachfragen
task.delay(GETFULL_AFTER, function()
	if ctx.StateTime == 0 then
		local reply = ctx.RequestFull("GetFull", nil, true)
		if reply.Ok and type(reply.State) == "table" then
			onState(reply.State, true)
		end
	end
end)

-- Willkommen (lokalisiert, mit der passenden Taste für das Gerät) – nach der Splash
task.delay(4.5, function()
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
