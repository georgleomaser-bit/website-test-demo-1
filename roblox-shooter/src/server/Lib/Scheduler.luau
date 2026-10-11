-- =====================================================================
--  CLUTCH CLASH – Der EINE Server-Takt (Server/Lib/Scheduler)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C5.1 (normales Modul, per require).
--  Muss-Regel 9: keine while-Schleife pro Spieler – alle Takte laufen hier über EINEN
--  RunService.Heartbeat-Anschluss.
--
--  Öffentliche API:
--    Scheduler.Every(name, hz, fn(dt))                       fn hz-mal pro Sekunde
--    Scheduler.EveryFrame(name, fn(dt))                      fn jeden Frame
--    Scheduler.Staggered(name, hz, items(), fn(item, dt))    verteilt die Items über die Frames,
--                                                            jedes Item hz-mal pro Sekunde
--    Scheduler.Stats(): { [name]: { AvgMs, MaxMs } }         Kosten pro Aufruf-Frame (Fenster 5 s),
--                                                            dazu "_Total" = ganzer Heartbeat-Schritt
--  Jede Funktion gibt zusätzlich eine Stopp-Funktion zurück (optional zu benutzen).
--
--  Regeln:
--    * jeder Callback läuft in pcall; Fehler höchstens alle 10 s pro Name im Output
--    * Frame-dt wird auf 0..0.25 s geklemmt (Hänger erzeugen keine Riesen-Sprünge).
--      Every/Staggered bekommen die (geklemmte) Zeit seit ihrem letzten Lauf, höchstens
--      max(0.25, 2 / hz) – ein 1-Hz-Takt bekommt also ~1.0 s.
--    * Callbacks dürfen NICHT yielden (task.wait usw.). Tut einer es doch, wird er bis zur
--      Rückkehr übersprungen und es gibt eine Warnung – die anderen Takte laufen weiter.
--    * Doppelter Name -> eindeutiger Name mit "#2", "#3" … (Warnung)
-- =====================================================================

local RunService = game:GetService("RunService")

local Scheduler = {}

export type Stat = { AvgMs: number, MaxMs: number }

type Job = {
	Name: string,
	Kind: "Every" | "Frame" | "Staggered",
	Interval: number, -- Sekunden zwischen zwei Läufen (Every) bzw. Ziel-Periode pro Item (Staggered)
	MaxDt: number,
	Acc: number,
	Since: number, -- Zeit seit dem letzten Lauf (Every)
	Fn: (...any) -> (),
	-- Staggered
	Items: (() -> { any })?,
	List: { any },
	Cursor: number,
	Budget: number,
	LastT: { [any]: number },
	-- Zustand
	Busy: boolean,
	Stopped: boolean,
	LastError: number,
	LastYieldWarn: number,
	-- Statistik (laufendes Fenster + zuletzt abgeschlossenes Fenster)
	SumMs: number,
	Count: number,
	MaxMs: number,
	Published: Stat?,
}

local MAX_FRAME_DT = 0.25
local ERROR_LOG_EVERY = 10
local STATS_WINDOW = 5
local MAX_JOBS = 200 -- Obergrenze (Schutz vor Endlos-Registrierung)

local jobs: { Job } = {}
local usedNames: { [string]: number } = {}
local connection: RBXScriptConnection? = nil
local frameId = 0
local needsCompact = false

local total = { SumMs = 0, Count = 0, MaxMs = 0, Published = nil :: Stat? }
local windowStart = os.clock()

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function logError(job: Job, err: any)
	local now = os.clock()
	if now - job.LastError >= ERROR_LOG_EVERY then
		job.LastError = now
		warn(("[Scheduler] Fehler in %s: %s"):format(job.Name, tostring(err)))
	end
end

local function warnYield(job: Job)
	local now = os.clock()
	if now - job.LastYieldWarn >= ERROR_LOG_EVERY then
		job.LastYieldWarn = now
		warn(("[Scheduler] %s hat geyieldet (task.wait o. ä.) – wird bis zur Rückkehr übersprungen"):format(job.Name))
	end
end

-- Einen Callback sicher aufrufen. Gibt false zurück, wenn er (noch) nicht fertig ist (yield).
local function call(job: Job, ...: any): boolean
	job.Busy = true
	local myFrame = frameId
	local ok, err = pcall(job.Fn, ...)
	job.Busy = false
	if not ok then
		logError(job, err)
	end
	-- Hat der Callback geyieldet, ist inzwischen ein neuer Frame gelaufen
	return myFrame == frameId
end

-- Staggered: eine Runde neu beginnen (frische Item-Liste, Zeitstempel nur für aktuelle Items behalten)
local function refreshList(job: Job)
	local getter = job.Items
	local list: { any } = {}
	if getter then
		local ok, result = pcall(getter)
		if ok and type(result) == "table" then
			list = result
		elseif not ok then
			logError(job, result)
		end
	end
	local snapshot = table.create(#list)
	local lastT: { [any]: number } = {}
	for i, item in ipairs(list) do
		snapshot[i] = item
		if item ~= nil then
			lastT[item] = job.LastT[item]
		end
	end
	job.List = snapshot
	job.LastT = lastT
	job.Cursor = 1
end

local function runStaggered(job: Job, dt: number, now: number): boolean
	if job.Cursor > #job.List then
		refreshList(job)
	end
	local count = #job.List
	if count == 0 then
		job.Budget = 0
		return true
	end
	-- n Items × hz pro Sekunde -> Anteil dieses Frames; nie mehr als die ganze Liste pro Frame
	job.Budget = math.min(job.Budget + count * dt / job.Interval, count)
	local steps = math.floor(job.Budget)
	job.Budget -= steps
	for _ = 1, steps do
		if job.Cursor > #job.List then
			refreshList(job)
			if #job.List == 0 then
				break
			end
		end
		local item = job.List[job.Cursor]
		job.Cursor += 1
		if item ~= nil then
			local last = job.LastT[item]
			local itemDt = if last then math.clamp(now - last, 0, job.MaxDt) else job.Interval
			job.LastT[item] = now
			if not call(job, item, itemDt) then
				return false
			end
		end
	end
	return true
end

local function compact()
	needsCompact = false
	local kept: { Job } = {}
	for _, job in ipairs(jobs) do
		if not job.Stopped then
			table.insert(kept, job)
		end
	end
	jobs = kept
end

local function record(target: { SumMs: number, Count: number, MaxMs: number }, ms: number)
	target.SumMs += ms
	target.Count += 1
	if ms > target.MaxMs then
		target.MaxMs = ms
	end
end

local function publishWindow()
	for _, job in ipairs(jobs) do
		if job.Count > 0 then
			job.Published = { AvgMs = job.SumMs / job.Count, MaxMs = job.MaxMs }
		end
		job.SumMs, job.Count, job.MaxMs = 0, 0, 0
	end
	if total.Count > 0 then
		total.Published = { AvgMs = total.SumMs / total.Count, MaxMs = total.MaxMs }
	end
	total.SumMs, total.Count, total.MaxMs = 0, 0, 0
end

local function onHeartbeat(rawDt: number)
	frameId += 1
	local myFrame = frameId
	local dt = math.clamp(if finite(rawDt) then rawDt else 0, 0, MAX_FRAME_DT)
	local frameStart = os.clock()
	local count = #jobs
	for i = 1, count do
		if frameId ~= myFrame then
			return -- dieser Frame hat geyieldet und wurde von neueren Frames überholt
		end
		local job = jobs[i]
		if job == nil or job.Stopped then
			continue
		end
		if job.Busy then
			warnYield(job)
			continue
		end
		local started = os.clock()
		local ran = false
		local finished = true
		if job.Kind == "Frame" then
			ran = true
			finished = call(job, dt)
		elseif job.Kind == "Every" then
			job.Acc += dt
			job.Since += dt
			if job.Acc >= job.Interval then
				local jobDt = math.min(job.Since, job.MaxDt)
				job.Since = 0
				-- Rest behalten (gleichmäßiger Takt), aber nie mehr als eine Periode Rückstand
				job.Acc = math.min(job.Acc - job.Interval, job.Interval)
				ran = true
				finished = call(job, jobDt)
			end
		else
			ran = true
			finished = runStaggered(job, dt, started)
		end
		if not finished then
			return
		end
		if ran then
			record(job, (os.clock() - started) * 1000)
		end
	end
	record(total, (os.clock() - frameStart) * 1000)
	if needsCompact then
		compact()
	end
	if frameStart - windowStart >= STATS_WINDOW then
		windowStart = frameStart
		publishWindow()
	end
end

local function uniqueName(name: string): string
	local base = if type(name) == "string" and name ~= "" then name else "Unbenannt"
	local used = usedNames[base]
	if used == nil then
		usedNames[base] = 1
		return base
	end
	used += 1
	usedNames[base] = used
	local result = base .. "#" .. used
	warn(("[Scheduler] Name %s doppelt registriert -> %s"):format(base, result))
	return result
end

local function ensureConnected()
	if connection == nil then
		connection = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

local function add(job: Job): () -> ()
	if #jobs >= MAX_JOBS then
		warn("[Scheduler] Zu viele Takte – " .. job.Name .. " wird ignoriert")
		return function() end
	end
	table.insert(jobs, job)
	ensureConnected()
	return function()
		if not job.Stopped then
			job.Stopped = true
			needsCompact = true
		end
	end
end

local function newJob(name: string, kind: "Every" | "Frame" | "Staggered", hz: number, fn: (...any) -> ()): Job
	local rate = if finite(hz) and hz > 0 then hz else 1
	local interval = 1 / rate
	return {
		Name = uniqueName(name),
		Kind = kind,
		Interval = interval,
		MaxDt = math.max(MAX_FRAME_DT, 2 * interval),
		Acc = 0,
		Since = 0,
		Fn = fn,
		Items = nil,
		List = {},
		Cursor = 1,
		Budget = 0,
		LastT = {},
		Busy = false,
		Stopped = false,
		LastError = -math.huge,
		LastYieldWarn = -math.huge,
		SumMs = 0,
		Count = 0,
		MaxMs = 0,
		Published = nil,
	}
end

-- fn(dt) hz-mal pro Sekunde (z. B. Matches 5 Hz, Pads 4 Hz, Aufräumen 1/30 Hz)
function Scheduler.Every(name: string, hz: number, fn: (dt: number) -> ()): () -> ()
	assert(type(fn) == "function", "Scheduler.Every: fn fehlt")
	return add(newJob(name, "Every", hz, fn :: any))
end

-- fn(dt) jeden Frame (z. B. Projektile)
function Scheduler.EveryFrame(name: string, fn: (dt: number) -> ()): () -> ()
	assert(type(fn) == "function", "Scheduler.EveryFrame: fn fehlt")
	return add(newJob(name, "Frame", 60, fn :: any))
end

-- Verteilt die Items über die Frames: jedes Item wird hz-mal pro Sekunde mit fn(item, dt) bearbeitet.
-- items() wird zu Beginn jeder Runde neu gefragt (Schnappschuss – Änderungen während der Runde sind egal).
function Scheduler.Staggered<T>(name: string, hz: number, items: () -> { T }, fn: (item: T, dt: number) -> ()): () -> ()
	assert(type(items) == "function", "Scheduler.Staggered: items fehlt")
	assert(type(fn) == "function", "Scheduler.Staggered: fn fehlt")
	local job = newJob(name, "Staggered", hz, fn :: any)
	job.Items = items :: any
	return add(job)
end

-- Kosten pro Takt (Millisekunden pro Frame, in dem er lief). "_Total" = gesamter Heartbeat-Schritt.
function Scheduler.Stats(): { [string]: Stat }
	local result: { [string]: Stat } = {}
	for _, job in ipairs(jobs) do
		if not job.Stopped then
			local published = job.Published
			if published then
				result[job.Name] = { AvgMs = published.AvgMs, MaxMs = published.MaxMs }
			elseif job.Count > 0 then
				result[job.Name] = { AvgMs = job.SumMs / job.Count, MaxMs = job.MaxMs }
			else
				result[job.Name] = { AvgMs = 0, MaxMs = 0 }
			end
		end
	end
	local published = total.Published
	if published then
		result._Total = { AvgMs = published.AvgMs, MaxMs = published.MaxMs }
	elseif total.Count > 0 then
		result._Total = { AvgMs = total.SumMs / total.Count, MaxMs = total.MaxMs }
	else
		result._Total = { AvgMs = 0, MaxMs = 0 }
	end
	return result
end

return Scheduler
