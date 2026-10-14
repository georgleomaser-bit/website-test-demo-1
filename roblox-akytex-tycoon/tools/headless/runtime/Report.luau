--!nocheck
-- =====================================================================
--  Headless-Harness · Report (Sammelstelle für Fehler, Warnungen, Infinite-Yields, unmocked/deprecated APIs)
--
--  Report.error{ message=, traceback=, ctx=, kind=, thread= }   unbehandelter Laufzeitfehler (dedupliziert nach
--                                                                Nachricht + erster Spiel-Position, mit Zähler)
--  Report.warn(msg, ctx, traceback?, kind?)                       Warnung (z. B. Roblox-Warnungen); kind
--                                                                "infiniteYield" landet zusätzlich in infiniteYields
--  Report.unmockedCall(className, member, kind)                  Aufruf einer laut API existierenden, aber nicht
--                                                                emulierten Methode (Stub gab nil zurück)
--  Report.deprecatedUse(name)                                     Nutzung veralteter API (wait/spawn/delay, …)
--  Report.harnessError(msg, traceback)                           Fehler IM Harness (Kategorie B)
--  Report.print(ctx, kind, text)                                 print/warn-Ausgabe des Spiels (Ringpuffer)
--  Report.setTrigger(label) / Report.trigger                     aktueller Auslöser (Szenario: Knopf, Request …)
--  Report.summary(), Report.toTable(), Report.renderText(), Report.emit(name, text) (Marker für run.py)
--
--  Einordnung: Fehler, deren oberster Frame im Harness liegt und die NICHT bewusst per Util.raise (Roblox-artiger
--  API-Fehler) geworfen wurden, gelten als Harness-Lücke (B). nil-Fehler nach einem unmocked-Aufruf im selben
--  Thread bekommen einen Hinweis (Stubs geben nil zurück -> möglicherweise Folgefehler, im Harness nachprüfen).
-- =====================================================================
return function(R)
	local Util = R.Util
	local Report = {}

	Report.errors = {} -- Liste eindeutiger Fehler (Reihenfolge des ersten Auftretens)
	Report.errorByKey = {}
	Report.warnings = {}
	Report.warningByKey = {}
	Report.infiniteYields = {}
	Report.unmocked = {} -- "Klasse:Member" -> {count, kind, locations}
	Report.deprecated = {} -- name -> {count, locations}
	Report.harness = {} -- Harness-interne Fehler
	Report.harnessByKey = {}
	Report.output = {} -- Ringpuffer der Spiel-Ausgaben
	Report.outputMax = 4000
	Report.outputDropped = 0
	Report.trigger = nil
	Report.scenario = nil
	Report.totalErrors = 0
	Report.totalWarnings = 0
	-- letzter unmocked-Aufruf je Thread (für Folgefehler-Hinweise)
	Report.lastUnmocked = setmetatable({}, { __mode = "k" })

	local function ctxName(ctx)
		if type(ctx) == "table" then
			return ctx.name or "?"
		end
		return ctx and tostring(ctx) or "harness"
	end
	Report.ctxName = ctxName

	function Report.setTrigger(label)
		Report.trigger = label
	end

	local function echo(line)
		if R.config.echo then
			print(line)
		end
	end

	--- erste Zeile eines Tracebacks, die eine Quelle hat
	local function topFrameSource(tb)
		if type(tb) ~= "string" then
			return nil
		end
		for line in string.gmatch(tb, "[^\n]+") do
			local src = string.match(line, "^(.-):%d+")
			if src then
				return src
			end
		end
		return nil
	end

	--- Traceback auf lesbare Zeilen kürzen: Harness-Frames entfernen (außer wenn nur Harness-Frames da sind)
	function Report.cleanTraceback(tb)
		if type(tb) ~= "string" then
			return ""
		end
		local game, all = {}, {}
		for line in string.gmatch(tb, "[^\n]+") do
			if line ~= "stack traceback:" and line ~= "stacktrace:" then
				all[#all + 1] = line
				local src = string.match(line, "^(.-):%d+")
				if src and not Util.isHarnessSource(src) then
					game[#game + 1] = line
				end
			end
		end
		if #game == 0 then
			return table.concat(all, "\n")
		end
		return table.concat(game, "\n")
	end

	function Report.error(info)
		local msg = Util.errToString(info.message)
		local tb = info.traceback or ""
		local loc = Util.firstGameFrame(tb) or Util.firstGameFrame(msg) or "?"
		local top = topFrameSource(tb)
		local deliberate = Util.lastRaised ~= nil and string.sub(msg, -#Util.lastRaised) == Util.lastRaised
		local category = "A"
		if top and Util.isHarnessSource(top) and not deliberate then
			category = "B"
		end
		local key = msg .. "@" .. loc
		Report.totalErrors += 1
		local e = Report.errorByKey[key]
		local thread = info.thread
		if e == nil then
			e = {
				message = msg,
				location = loc,
				traceback = Report.cleanTraceback(tb),
				rawTraceback = tb,
				ctx = ctxName(info.ctx),
				kind = info.kind or "thread",
				category = category,
				count = 0,
				firstTime = R.Sched and R.Sched.now or 0,
				triggers = {},
				scenario = Report.scenario,
				hint = nil,
			}
			-- Stubs geben nil zurück: nil-Fehler nach einem unmocked-Aufruf im selben Thread sind verdächtig
			if thread and Report.lastUnmocked[thread] and string.find(msg, "nil", 1, true) then
				e.hint = "nach unmocked API-Aufruf "
					.. Report.lastUnmocked[thread]
					.. " (möglicherweise Folgefehler des Stubs)"
			end
			Report.errorByKey[key] = e
			Report.errors[#Report.errors + 1] = e
			echo(string.format("[FEHLER %s] %s\n%s", e.ctx, msg, e.traceback))
		end
		e.count += 1
		local trig = Report.trigger
		if trig and #e.triggers < 10 and not table.find(e.triggers, trig) then
			e.triggers[#e.triggers + 1] = trig
		end
		return e
	end

	-- ---------------------------------------------------------------------------------------------
	--  Abgefangene Fehler (pcall/xpcall im Spiel-Code)
	--  Art: "api" (Roblox-API-Fehler per Util.raise), "runtime" (Luau-Laufzeitfehler: attempt to …, invalid
	--  argument …), "thrown" (vom Spiel selbst mit error() geworfen – nur Information), "harness" (oberster Frame
	--  im Harness, nicht bewusst geworfen -> Kategorie B).
	-- ---------------------------------------------------------------------------------------------
	Report.caughtList = {}
	Report.caughtByKey = {}
	Report.totalCaught = 0
	local runtimePatterns = {
		"attempt to ",
		"invalid argument #",
		"bad argument #",
		"missing argument #",
		"Argument %d+ missing or nil",
		"is not a valid member of",
		"stack overflow",
		"Unable to ",
		"cannot resume",
		"table index is nil",
		"table index is NaN",
		"string expected",
		"number expected",
		"invalid value",
		"Requested module was required recursively",
		"Module code did not return exactly one value",
		"Expected ':' not '.'",
		"is not a valid Service name",
		"The Parent property of",
		"cannot be assigned to",
		"lacking capability",
	}
	function Report.caught(e, level)
		Report.totalCaught += 1
		local msg = Util.errToString(e)
		if type(e) == "string" and string.find(msg, "Requested module experienced an error while loading", 1, true) then
			return -- Originalfehler wurde schon beim Laden gemeldet
		end
		-- Ort: erster Spiel-Frame ab dem Fehlerort (der pcall-Wrapper in Globals.luau ist transparent)
		local loc = nil
		local lvl = (level or 2) + 1
		local topSrc = nil
		local errSrc = debug.info(lvl, "s")
		local callerSrc = debug.info(lvl + 1, "s")
		local callerFn = debug.info(lvl + 1, "n")
		while true do
			local src, line = debug.info(lvl, "sl")
			if src == nil then
				break
			end
			if topSrc == nil and src ~= "[C]" and not string.find(src, "runtime/Globals.luau", 1, true) then
				topSrc = src
			end
			if not Util.isHarnessSource(src) then
				loc = src .. ":" .. tostring(line)
				break
			end
			lvl += 1
		end
		-- eingebaute Funktion direkt per pcall aufgerufen (pcall(string.format, …), pcall(require, …)): der
		-- Spiel-Code rechnet mit dem Fehlschlag -> nur Information
		local directBuiltin = errSrc == "[C]" and callerSrc == "[C]" and callerFn == "xpcall"
		local key = msg .. "@" .. tostring(loc)
		local c = Report.caughtByKey[key]
		if c then
			c.count += 1
			local trig = Report.trigger
			if trig and #c.triggers < 10 and not table.find(c.triggers, trig) then
				c.triggers[#c.triggers + 1] = trig
			end
			return
		end
		local kind = "thrown"
		local deliberate = Util.lastRaised ~= nil and type(e) == "string" and string.sub(msg, -#Util.lastRaised) == Util.lastRaised
		if deliberate then
			kind = "api"
		elseif type(e) == "string" then
			for _, pat in runtimePatterns do
				if string.find(msg, pat) then
					kind = "runtime"
					break
				end
			end
		end
		if kind ~= "api" and topSrc and Util.isHarnessSource(topSrc) and type(e) == "string" then
			kind = "harness"
		end
		if directBuiltin and kind ~= "api" then
			kind = "thrown"
		end
		-- per --faults injizierter Dienst-Fehler: vom Spiel abgefangen = erwünschtes Verhalten (nur Information)
		if kind == "api" and Util.lastInjected ~= nil and string.sub(msg, -#Util.lastInjected) == Util.lastInjected then
			kind = "injected"
		end
		local tb = debug.traceback(msg, (level or 2) + 1)
		local co = coroutine.running()
		c = {
			message = msg,
			location = loc or Util.firstGameFrame(msg) or "?",
			traceback = Report.cleanTraceback(tb),
			rawTraceback = tb,
			ctx = ctxName(R.Sched and R.Sched.ctx() or nil),
			kind = kind,
			count = 1,
			firstTime = R.Sched and R.Sched.now or 0,
			triggers = Report.trigger and { Report.trigger } or {},
			scenario = Report.scenario,
		}
		if co and Report.lastUnmocked[co] and string.find(msg, "nil", 1, true) then
			c.hint = "nach unmocked API-Aufruf " .. Report.lastUnmocked[co] .. " (möglicherweise Folgefehler des Stubs)"
		end
		Report.caughtByKey[key] = c
		Report.caughtList[#Report.caughtList + 1] = c
		if R.config.echo and kind ~= "thrown" then
			print(string.format("[ABGEFANGEN %s/%s] %s\n%s", c.ctx, kind, msg, c.traceback))
		end
	end

	function Report.warn(msg, ctx, traceback, kind)
		msg = Util.errToString(msg)
		local loc = Util.firstGameFrame(traceback) or "?"
		local key = (kind or "warn") .. ":" .. msg .. "@" .. loc
		Report.totalWarnings += 1
		local w = Report.warningByKey[key]
		if w == nil then
			w = {
				message = msg,
				location = loc,
				traceback = Report.cleanTraceback(traceback),
				ctx = ctxName(ctx),
				kind = kind or "warn",
				count = 0,
				firstTime = R.Sched and R.Sched.now or 0,
				trigger = Report.trigger,
				scenario = Report.scenario,
			}
			local co = coroutine.running()
			if co and Report.lastUnmocked[co] and string.find(msg, "nil", 1, true) then
				w.hint = "nach unmocked API-Aufruf "
					.. Report.lastUnmocked[co]
					.. " (möglicherweise Folge eines Stubs)"
			end
			Report.warningByKey[key] = w
			Report.warnings[#Report.warnings + 1] = w
			if kind == "infiniteYield" then
				Report.infiniteYields[#Report.infiniteYields + 1] = w
			end
			echo(string.format("[WARNUNG %s] %s", w.ctx, msg))
		end
		w.count += 1
		return w
	end

	function Report.unmockedCall(className, member, kind)
		local key = className .. ":" .. member
		local u = Report.unmocked[key]
		if u == nil then
			u = {
				key = key,
				className = className,
				member = member,
				kind = kind or "method",
				count = 0,
				locations = {},
			}
			Report.unmocked[key] = u
		end
		u.count += 1
		local loc = Util.gameLocation()
		if loc then
			u.locations[loc] = (u.locations[loc] or 0) + 1
		end
		local co = coroutine.running()
		if co then
			Report.lastUnmocked[co] = key .. (loc and (" @ " .. loc) or "")
		end
	end

	function Report.deprecatedUse(name)
		local d = Report.deprecated[name]
		if d == nil then
			d = { name = name, count = 0, locations = {} }
			Report.deprecated[name] = d
		end
		d.count += 1
		local loc = Util.gameLocation()
		if loc then
			d.locations[loc] = (d.locations[loc] or 0) + 1
		end
	end

	function Report.harnessError(msg, traceback)
		msg = Util.errToString(msg)
		local key = msg
		local h = Report.harnessByKey[key]
		if h == nil then
			h = { message = msg, traceback = traceback or "", count = 0, trigger = Report.trigger }
			Report.harnessByKey[key] = h
			Report.harness[#Report.harness + 1] = h
			echo("[HARNESS-FEHLER] " .. msg .. "\n" .. (traceback or ""))
		end
		h.count += 1
		return h
	end

	function Report.print(ctx, kind, text)
		local out = Report.output
		if #out >= Report.outputMax then
			table.remove(out, 1)
			Report.outputDropped += 1
		end
		local line = { t = R.Sched and R.Sched.now or 0, ctx = ctxName(ctx), kind = kind, text = text }
		out[#out + 1] = line
		if R.config.echoOutput then
			print(string.format("[%s %s %.2f] %s", kind, line.ctx, line.t, text))
		end
	end

	--- Ausgabe-Zeilen suchen (z. B. Szenario prüft "Server gestartet")
	function Report.findOutput(pattern, ctxPrefix)
		for _, line in Report.output do
			if
				(ctxPrefix == nil or string.sub(line.ctx, 1, #ctxPrefix) == ctxPrefix)
				and string.find(line.text, pattern)
			then
				return line
			end
		end
		return nil
	end

	local function countKeys(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	function Report.summary()
		local a, b = 0, 0
		for _, e in Report.errors do
			if e.category == "A" then
				a += 1
			else
				b += 1
			end
		end
		return {
			errorsTotal = Report.totalErrors,
			errorsUnique = #Report.errors,
			errorsGame = a,
			errorsHarnessSuspect = b,
			warningsTotal = Report.totalWarnings,
			warningsUnique = #Report.warnings,
			infiniteYields = #Report.infiniteYields,
			unmockedApis = countKeys(Report.unmocked),
			deprecatedApis = countKeys(Report.deprecated),
			harnessErrors = #Report.harness,
			simTime = R.Sched and R.Sched.now or 0,
		}
	end

	function Report.toTable()
		local unm, dep = {}, {}
		for _, u in Report.unmocked do
			unm[#unm + 1] = u
		end
		table.sort(unm, function(x, y)
			return x.count > y.count
		end)
		for _, d in Report.deprecated do
			dep[#dep + 1] = d
		end
		table.sort(dep, function(x, y)
			return x.count > y.count
		end)
		return {
			summary = Report.summary(),
			scenario = Report.scenario,
			errors = Report.errors,
			warnings = Report.warnings,
			unmocked = unm,
			deprecated = dep,
			harness = Report.harness,
		}
	end

	function Report.renderText()
		local s = Report.summary()
		local L = {}
		L[#L + 1] = string.format(
			"Fehler gesamt %d (eindeutig %d: Spiel %d, Harness-Verdacht %d) · Warnungen %d (eindeutig %d) · Infinite-Yields %d · unmocked APIs %d · deprecated APIs %d · Harness-Fehler %d · Simulationszeit %.1f s",
			s.errorsTotal,
			s.errorsUnique,
			s.errorsGame,
			s.errorsHarnessSuspect,
			s.warningsTotal,
			s.warningsUnique,
			s.infiniteYields,
			s.unmockedApis,
			s.deprecatedApis,
			s.harnessErrors,
			s.simTime
		)
		for i, e in Report.errors do
			L[#L + 1] = ""
			L[#L + 1] = string.format("[%s%d] (%s, %s, %dx) %s", e.category, i, e.ctx, e.kind, e.count, e.message)
			if #e.triggers > 0 then
				L[#L + 1] = "    Auslöser: " .. table.concat(e.triggers, " | ")
			end
			if e.hint then
				L[#L + 1] = "    Hinweis: " .. e.hint
			end
			for line in string.gmatch(e.traceback, "[^\n]+") do
				L[#L + 1] = "    " .. line
			end
		end
		for _, w in Report.warnings do
			L[#L + 1] = string.format("[W] (%s, %s, %dx) %s", w.ctx, w.kind, w.count, w.message)
			if w.hint then
				L[#L + 1] = "    Hinweis: " .. w.hint
			end
		end
		for _, h in Report.harness do
			L[#L + 1] = string.format("[HARNESS] (%dx) %s", h.count, h.message)
		end
		return table.concat(L, "\n")
	end

	--- Gibt einen Block mit Markern aus, den run.py in eine Datei zerlegt
	function Report.emit(name, text)
		print("@@BEGIN " .. name .. "@@")
		print(text)
		print("@@END " .. name .. "@@")
	end

	return Report
end
