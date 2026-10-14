--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Roblox-Harness · Laufzeit (Loader + interne API-Dokumentation)
--
--  Benutzung (Luau-CLI, aus dem Projektordner):
--      local R = require("./tools/headless/runtime").boot({ frameRate = 30, startUnix = 1791972000, seed = 1 })
--  boot() lädt die Module in fester Reihenfolge und liefert die Laufzeit-Tabelle R (Singleton je Prozess):
--
--    R.config   Konfiguration (Defaults unten; per boot{…} überschreibbar)
--    R.api      api_data.luau (von gen_api.py erzeugt)
--    R.Util     Fehler mit Spiel-Position (Util.raise), Argument-Prüfungen, typeof/type, float32, Formatierung
--    R.Report   Sammelstelle: Report.error/warn/unmockedCall/deprecatedUse/harnessError/print, summary/toTable/emit
--    R.Sched    simulierte Zeit + Threads + Kontexte + Deferred-Queue (task.*, wait/spawn/delay, step/run/runUntil)
--    R.Signal   RBXScriptSignal/RBXScriptConnection mit Deferred-Verhalten
--    R.DT       alle Datentypen (DT.Vector3 …, DT.make.*, DT.is.*, DT.json)
--    R.Enum     Enum-System (Enum.global, Enum.item/coerce/fromValue)
--    R.Inst     Instanz-System + Klassenverhalten (Inst.define, Inst.registerService, Inst.newDataModel, …)
--    R.Globals  Script-Umgebungen + require (Globals.makeEnv/startScript/require, Globals.moduleProvider)
--
--  ── Kontexte (Server/Client in einer VM) ─────────────────────────────────────────────────────────
--  Ein Kontext ist eine Tabelle { kind = "server"|"client"|"harness", name, isServer, isClient, player, game,
--  G, shared, modules, data }. Anlegen: local srv = R.Sched.newContext{ kind = "server", name = "server" }.
--  Jeder Thread hat genau einen Kontext (R.Sched.threadCtx[co]); R.Sched.ctx() liefert den des laufenden Threads
--  (Haupt-Thread: R.Sched.mainCtx). task.spawn/defer/delay, alte spawn/delay, Signal-Handler (Kontext des
--  VERBINDENDEN Threads) und coroutine.create/wrap aus Spiel-Code erben den Kontext automatisch.
--  Spiel-Code in einem Kontext starten: R.Sched.spawnHandler(fn, ctx, label, …) oder R.Sched.invoke(ctx, fn, …)
--  (mit Ergebnis-Handle; R.Sched.await(h) simuliert bis fertig). Skripte: R.Globals.startScript(ctx, inst, src,
--  "src/…/Datei.luau"). require-Cache, _G und shared sind je Kontext getrennt (wie getrennte Roblox-VMs).
--  RunService:IsServer/IsClient, Players.LocalPlayer usw. sollen R.Sched.ctx() auswerten.
--  Sichtbarkeit Server/Client: entweder getrennte DataModels je Kontext (Inst.newDataModel je Kontext + eigener
--  Replikator über Inst.observe – empfohlen, siehe README) oder gemeinsamer Baum + Inst.setVisibilityFilter.
--
--  ── Fehler erfassen ──────────────────────────────────────────────────────────────────────────────
--  Unbehandelte Fehler in Spiel-Threads fängt R.Sched.newThread per xpcall (Traceback am Fehlerort) und meldet
--  sie mit R.Report.error{message, traceback, ctx, thread, kind}; dedupliziert nach Nachricht + erster Spiel-
--  Position ("src/…:Zeile"), mit Zähler und Auslöser (R.Report.setTrigger("Klick: …")). Roblox-artige API-Fehler
--  wirft Harness-Code mit R.Util.raise(msg) – die Position zeigt dann auf die aufrufende Spiel-Zeile, und der
--  Report ordnet sie als Spiel-Bug (A) ein. Andere Fehler, deren oberster Frame im Harness liegt, gelten als
--  Harness-Lücke (B). Fehler in Harness-Hooks/Observern: R.Report.harnessError. Warnungen: R.Report.warn
--  (kind "infiniteYield" bei WaitForChild > 5 s, "gameWarn" für warn() des Spiels).
--  Nicht emulierte, aber existierende API: Stub + R.Report.unmockedCall(class, member) (Folgefehler bekommen
--  einen Hinweis). Veraltete API: R.Report.deprecatedUse(name).
--
--  ── Service anlegen ──────────────────────────────────────────────────────────────────────────────
--      R.Inst.registerService("TweenService", {
--          methods = { Create = function(self, inst, info, goals) … end },  -- nur laut API existierende Member
--          props = { … }, callbacks = { … }, init = function(inst, M) end,
--          setup = function(service, M, game) end,                         -- je DataModel einmal
--      })
--  Klassen ohne Service-Tag: R.Inst.define(className, spec) (gleiches Format, ohne setup). Interner Zustand je
--  Instanz: getmetatable(inst) (M.props, M.ext, …) bzw. R.Inst.meta(inst). Property-Änderungen aus Harness-Code:
--  R.Inst.setProp (mit Typprüfung) / R.Inst.rawSet; Events feuern: R.Inst.fire(inst, "Name", …) (deferred).
--  Frame-Hooks: R.Sched.addHook("postSimulation", fn, "RunService.Heartbeat") usw. (Phasen siehe Scheduler).
-- =====================================================================
local R = {}
local booted = false

R.defaults = {
	frameRate = 30, -- Simulationsschritte pro Sekunde
	startUnix = 1791972000, -- simulierte Startzeit (UTC-Sekunden); Szenarien können z. B. Samstag 17:59 Berlin setzen
	seed = 1, -- Zufalls-Seed (math.random, Random.new() ohne Seed, BrickColor.random)
	viewport = { 1280, 720 }, -- Client-Viewport für GUI-Geometrie und Kamera
	topInset = 58, -- Roblox-Topbar (ScreenGui mit IgnoreGuiInset = false)
	infiniteYieldAfter = 5, -- Sekunden bis zur "Infinite yield possible"-Warnung
	echo = false, -- Fehler/Warnungen sofort auf stdout ausgeben
	echoOutput = false, -- print/warn des Spiels sofort ausgeben
}

local function harnessRootFromChunk()
	local src = debug.info(1, "s") or ""
	-- ".../tools/headless/runtime/init.luau" -> ".../tools/headless/"
	local root = string.match(src, "^(.*)runtime/init%.luau$") or string.match(src, "^(.*)runtime/init%.lua$")
	return root or ""
end

function R.boot(config)
	if booted then
		return R
	end
	booted = true
	local cfg = {}
	for k, v in R.defaults do
		cfg[k] = v
	end
	if config then
		for k, v in config do
			cfg[k] = v
		end
	end
	R.config = cfg
	R.root = harnessRootFromChunk()
	R.api = require("./api_data")
	R.Util = require("@self/Util")(R)
	R.Util.harnessRoots = { R.root }
	R.Report = require("@self/Report")(R)
	R.Sched = require("@self/Scheduler")(R)
	R.Signal = require("@self/Signal")(R)
	R.DT = require("@self/Datatypes")(R)
	R.Enum = require("@self/Enum")(R)
	R.Inst = require("@self/Instance")(R)
	R.Globals = require("@self/Globals")(R)
	math.randomseed(cfg.seed)
	R.rng = R.DT.Random.new(cfg.seed)
	return R
end

return R
