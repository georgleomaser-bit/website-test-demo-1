-- =====================================================================
--  AKYTEX TYCOON – Hooks: kleiner Signal-Hub für alle Client-Module (Client/Modules/Hooks)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.2 (CC 1:1, REUSE §3.18).
--
--  Öffentliche API:
--    Hooks.On(name, fn): () -> ()   anmelden, gibt die Trenn-Funktion zurück
--    Hooks.Once(name, fn)           nur beim nächsten Feuern
--    Hooks.Fire(name, ...)          jeder Listener in pcall (ein Fehler stoppt die anderen nicht)
--    Hooks.Count(name?): number     Anzahl Listener (Debug)
--    Hooks.Init(ctx) / Hooks.Start() (Modul-Form §C7.1, hier ohne Aufgabe)
--
--  Eingefrorene Ereignisse (§C7.2, der Vertrags-Prüfer warnt bei unbekannten):
--    "State"(state, changedKeys) · "Notify"(text, kind) · "Effect:<Name>"(strength, data) ·
--    "WindowOpened"/"WindowClosed"(name) · "Settings"(settings) · "Input"(kind) · "PhotoMode"(on) ·
--    "Quality"(tier) · "Quotes"(frame) · "Market:<Kind>"(data) · "World:<Kind>"(data) · "Replay"(tick, close, phase) ·
--    "Plot:Enter"/"Plot:Leave"(plotId, ownerUserId) · "Tower:Built"/"Tower:Stage"(n) · "Vehicle:Enter"/"Vehicle:Exit"(model?) ·
--    "Terminal:Instrument"(instId)
--  changedKeys bei "State": Liste der Schlüssel UND Set (changed[key] == true) – beides geht.
-- =====================================================================

local Hooks = {}

type Listener = { Fn: (...any) -> (), Once: boolean, Alive: boolean }

local MAX_LISTENERS = 256 -- pro Ereignis; mehr deutet auf ein Leck hin (warn einmal)
local ERROR_LOG_GAP = 10 -- Fehler je Ereignis höchstens alle 10 s loggen

local listeners: { [string]: { Listener } } = {}
local lastErrorAt: { [string]: number } = {}
local warnedFull: { [string]: boolean } = {}

local function add(name: string, fn: (...any) -> (), once: boolean): () -> ()
	if type(name) ~= "string" or type(fn) ~= "function" then
		warn("[Hooks] On/Once: Name (string) und Funktion erwartet")
		return function() end
	end
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	if #list >= MAX_LISTENERS and not warnedFull[name] then
		warnedFull[name] = true
		warn(("[Hooks] Sehr viele Listener für %s (%d) – wird irgendwo nie getrennt?"):format(name, #list))
	end
	local entry: Listener = { Fn = fn, Once = once, Alive = true }
	table.insert(list, entry)
	return function()
		if not entry.Alive then
			return
		end
		entry.Alive = false
		local current = listeners[name]
		if current then
			local index = table.find(current, entry)
			if index then
				table.remove(current, index)
			end
			if #current == 0 then
				listeners[name] = nil
			end
		end
	end
end

-- Anmelden; Rückgabe trennt wieder ab
function Hooks.On(name: string, fn: (...any) -> ()): () -> ()
	return add(name, fn, false)
end

-- Nur beim nächsten Feuern aufrufen
function Hooks.Once(name: string, fn: (...any) -> ())
	add(name, fn, true)
end

-- Alle Listener aufrufen (Schnappschuss der Liste: An-/Abmelden während Fire ist erlaubt)
function Hooks.Fire(name: string, ...: any)
	local list = listeners[name]
	if not list or #list == 0 then
		return
	end
	local snapshot = table.clone(list)
	for _, entry in ipairs(snapshot) do
		if entry.Alive then
			if entry.Once then
				entry.Alive = false
				local index = table.find(list, entry)
				if index then
					table.remove(list, index)
				end
			end
			local ok, err = pcall(entry.Fn, ...)
			if not ok then
				local now = os.clock()
				if now - (lastErrorAt[name] or -math.huge) >= ERROR_LOG_GAP then
					lastErrorAt[name] = now
					warn(("[Hooks] Fehler in einem Listener von %s: %s"):format(name, tostring(err)))
				end
			end
		end
	end
	if #list == 0 and listeners[name] == list then
		listeners[name] = nil
	end
end

function Hooks.Count(name: string?): number
	if name then
		local list = listeners[name]
		return if list then #list else 0
	end
	local total = 0
	for _, list in pairs(listeners) do
		total += #list
	end
	return total
end

function Hooks.Init(_ctx: any) end

function Hooks.Start() end

return Hooks
