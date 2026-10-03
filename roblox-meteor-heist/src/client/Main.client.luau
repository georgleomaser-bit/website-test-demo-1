-- =====================================================================
--  METEOR HEIST – Client (alles, was der Spieler sieht)
--  Dieses Skript startet nur die Module im Ordner "Modules" und verbindet sie mit dem Server:
--    UI         Baukasten (Knöpfe, Fenster, Toasts, zählende Zahlen)
--    Hud        Knöpfe links/rechts (mit Badges), Schritte + Geld, Banner (Schauer, Egg Rush),
--               Wegweiser (Base beim Tragen, nächstes Ei), Prompt-Hinweis am Förderband
--    Windows    Shop (Gamepässe / Boosts / Gadgets), Laufbänder, Rebirth, Tagesbonus, Alien-Index
--    Rewards    🎁 Geschenke, 🎡 Glücksrad, 📜 Tagesaufgaben
--    Effects    fliegende Zahlen, Lieferflug, Schlüpf-Explosion, Hatch-Karte, Wackeln, Konfetti
--    WorldFX    Laufband-Meteore, Streifen, wippende Aliens, Regenbogen, Schlüpf-Countdown
--    Prompts    Klauen/Kaufen/Verkaufen-Prompts passend ein-/ausblenden
--    Fly, PhotoMode, AdminPanel (nur für Admins)
--  Die gesamte Oberfläche wird per Code gebaut – du musst nichts in Studio zusammenklicken.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Util = require(Shared:WaitForChild("Util"))
local Aliens = require(Shared:WaitForChild("Aliens")) :: any

local Modules = script.Parent:WaitForChild("Modules")
local UI = require(Modules:WaitForChild("UI"))
local Hud = require(Modules:WaitForChild("Hud"))
local Windows = require(Modules:WaitForChild("Windows"))
local Rewards = require(Modules:WaitForChild("Rewards"))
local Effects = require(Modules:WaitForChild("Effects"))
local WorldFX = require(Modules:WaitForChild("WorldFX"))
local Prompts = require(Modules:WaitForChild("Prompts"))
local Fly = require(Modules:WaitForChild("Fly"))
local PhotoMode = require(Modules:WaitForChild("PhotoMode"))
local AdminPanel = require(Modules:WaitForChild("AdminPanel"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local Remotes = {
	Notify = RemotesFolder:WaitForChild("Notify") :: RemoteEvent,
	State = RemotesFolder:WaitForChild("State") :: RemoteEvent,
	Effect = RemotesFolder:WaitForChild("Effect") :: RemoteEvent,
	Request = RemotesFolder:WaitForChild("Request") :: RemoteFunction,
	Admin = RemotesFolder:WaitForChild("Admin") :: RemoteFunction,
}

-- ---------------------------------------------------------------------
-- GRUNDGERÜST
-- ---------------------------------------------------------------------
local gui = UI.Create("ScreenGui", {
	Name = "MeteorHeistUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
	Parent = player:WaitForChild("PlayerGui"),
}) :: ScreenGui
UI.Init(gui)

-- Gemeinsamer "Rucksack" für alle Module
local ctx = {
	Player = player,
	Config = Config,
	Util = Util,
	Aliens = Aliens,
	Remotes = Remotes,
	Gui = gui,
	State = nil :: any, -- letzte Daten vom Server
	StateTime = os.clock(), -- wann der letzte State ankam (Countdowns darin gelten ab dann)
	Toast = UI.Toast,
	Request = nil :: any,
	RequestFull = nil :: any,
	Hooks = {} :: { [string]: (number) -> () },
	Hud = Hud,
	Windows = Windows,
	Rewards = Rewards,
	Effects = Effects,
	Prompts = Prompts,
	Fly = Fly,
	PhotoMode = PhotoMode,
}

-- Anfrage an den Server mit ganzer Antwort: (Erfolg, Antwort-Tabelle oder nil).
-- silent = true: keinen Toast zeigen (z.B. Glücksrad – Gewinn erst nach dem Drehen anzeigen).
function ctx.RequestFull(action: string, arg: any?, silent: boolean?): (boolean, { [string]: any }?)
	local ok, result = pcall(function()
		return Remotes.Request:InvokeServer(action, arg)
	end)
	if ok and type(result) == "table" then
		if not silent and type(result.Message) == "string" and result.Message ~= "" then
			UI.Toast(result.Message, if result.Ok then "Success" else "Error")
		end
		return result.Ok == true, result
	end
	if not silent then
		UI.Toast("📡 Keine Antwort vom Server – nochmal versuchen!", "Error")
	end
	return false, nil
end

-- Anfrage an den Server (Rebirth, Daily, Collect, Home, Treadmills, ClaimGift, ClaimQuest,
-- BuyGadget ...). Gibt true bei Erfolg zurück.
function ctx.Request(action: string, arg: any?): boolean
	local ok = ctx.RequestFull(action, arg)
	return ok
end

ctx.Hooks.OnSteps = function(_amount: number)
	Hud.PulseSteps()
end
ctx.Hooks.OnCash = function(_amount: number)
	Hud.PulseCash()
end

-- ---------------------------------------------------------------------
-- MODULE STARTEN
-- ---------------------------------------------------------------------
Effects.Init(ctx)
Windows.Init(ctx)
Rewards.Init(ctx)
Hud.Init(ctx)
Fly.Init(UI.Toast)
PhotoMode.Init(ctx)

-- Welt-Sachen brauchen die Map (wird vom Server gebaut) -> im Hintergrund warten
task.spawn(function()
	local map = workspace:WaitForChild("MeteorHeistMap", 120)
	if not map then
		warn("[Client] MeteorHeistMap nicht gefunden – Welt-Animationen aus")
		return
	end
	Hud.SetMap(map)
	Prompts.Init(map, ctx)
	WorldFX.Init(ctx, map)
	if ctx.State then
		WorldFX.UpdateTreadmills(tonumber(ctx.State.Steps) or 0, ctx.State.BestTreadmill)
	end
end)

-- ---------------------------------------------------------------------
-- DATEN VOM SERVER
-- ---------------------------------------------------------------------
local function refreshAll()
	local state = ctx.State
	if not state then
		return
	end
	Hud.Refresh(state)
	Windows.Refresh(state)
	Prompts.OnState(state)
	WorldFX.UpdateTreadmills(tonumber(state.Steps) or 0, state.BestTreadmill)
end

-- Selten geänderte Teile (Index, Pässe, Statistik) schickt der Server nur bei Änderung mit.
-- Fehlen sie in einem Paket, gelten die zuletzt bekommenen weiter.
local STICKY_KEYS = { "Index", "Passes", "Stats" }

Remotes.State.OnClientEvent:Connect(function(newState)
	if type(newState) ~= "table" then
		return
	end
	local old = ctx.State
	if old then
		for _, key in ipairs(STICKY_KEYS) do
			if newState[key] == nil then
				newState[key] = old[key]
			end
		end
	end
	ctx.State = newState
	ctx.StateTime = os.clock()
	refreshAll()
end)
Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	UI.Toast(tostring(text), if type(kind) == "string" then kind else "Info")
end)
Remotes.Effect.OnClientEvent:Connect(function(name, strength, data)
	Effects.Play(name, strength, data)
end)

-- Jede Sekunde: Banner, Badges, Countdowns (Tagesbonus, Geschenke, Gratis-Dreh, Aufgaben)
local function tick()
	Hud.Tick()
	Rewards.Tick()
	local state = ctx.State
	if state and state.DailyReady == false then
		state.DailyIn = math.max(0, (tonumber(state.DailyIn) or 0) - 1)
		if state.DailyIn == 0 then
			state.DailyReady = true
			Hud.Refresh(state)
		end
		Windows.RefreshDaily(state)
	end
end
task.spawn(function()
	while true do
		-- Ein Fehler darf die Schleife nicht für immer anhalten
		local ok, err = pcall(tick)
		if not ok then
			warn("[Client] Tick-Fehler: " .. tostring(err))
		end
		task.wait(1)
	end
end)

-- ---------------------------------------------------------------------
-- ADMIN-PANEL (nur wenn der Server dich als Admin markiert)
-- ---------------------------------------------------------------------
local function checkAdmin()
	if player:GetAttribute("IsAdmin") == true then
		AdminPanel.Build(ctx)
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(checkAdmin)
checkAdmin()

UI.Toast("☄️ Willkommen bei " .. tostring(Config.GameName) .. "! Klau Eier am Förderband [E] – gratis!", "Event")
task.delay(4, function()
	UI.Toast("🏃 Schnell heimtragen – oder kauf sie mit [F], dann werden sie geliefert!", "Info")
end)
task.delay(8, function()
	UI.Toast("🐣 In deiner Base schlüpfen Aliens – die bringen dir Geld!", "Info")
end)
