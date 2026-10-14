--!nocheck
-- =====================================================================
--  Headless-Harness · Scheduler (simulierte Zeit, Threads, Kontexte, Deferred-Queue)
--
--  Zeit: S.now (Sekunden seit Start, simuliert), S.frame, S.dt (Standard 1/30 s). S.step(dt) rückt einen Frame
--  vor; S.run(sekunden) / S.runUntil(pred, timeout) mehrere. Uhren: S.unix(), S.unixMillis() (Startzeit
--  R.config.startUnix + S.now) – Grundlage für tick/os.time/DateTime.now/GetServerTimeNow.
--
--  Frame-Phasen (in dieser Reihenfolge; Module hängen sich mit S.addHook(phase, fn, name) ein):
--    network -> input -> render -> legacyWait* -> preAnimation -> preSimulation -> physics -> postSimulation
--    -> timers* -> late          (* = vom Scheduler selbst: alte wait()/spawn/delay bzw. task.wait/task.delay)
--  RunService (späteres Modul) feuert in render (RenderStepped/PreRender, nur Client), preSimulation (Stepped),
--  postSimulation (Heartbeat). Nach jedem Hook wird die Deferred-Queue geleert.
--
--  Threads: S.newThread(fn, ctx, label, onError) erzeugt einen Spiel-Thread (xpcall + Traceback; Fehler landen
--  dedupliziert in Report). S.spawn/S.defer/S.delay/S.wait/S.cancel = task.*-Semantik. S.resume(co, …) ist der
--  einzige Weg, wie der Harness Threads fortsetzt (zählt Verschachtelung, leert danach die Deferred-Queue).
--
--  Kontexte: Jeder Thread hat einen Kontext (S.threadCtx[co]); S.ctx() liefert den des laufenden Threads.
--  Neue Threads (task.spawn/defer/delay, Signal-Handler, coroutine.create/wrap über Globals) ERBEN den Kontext
--  des erzeugenden/verbindenden Threads. Kontext = { kind = "server"|"client"|"harness", name, isServer,
--  isClient, player, game, G, shared, modules, data }. S.newContext{…} legt einen an; S.mainCtx gilt für Code
--  im Haupt-Thread (Harness).
--
--  Nicht-yieldende Callbacks: S.callNoYield(fn, …) -> (ok, …) bzw. (false, msg, traceback); Yield darin ->
--  Fehler "attempt to yield across metamethod/C-call boundary" (wie Roblox bei UpdateAsync-Transform usw.).
-- =====================================================================
return function(R)
	local Util = R.Util
	local Report = R.Report
	local S = {}

	S.now = 0
	S.frame = 0
	S.dt = 1 / (R.config.frameRate or 30)
	S.startUnix = R.config.startUnix or os.time()

	S.threadCtx = setmetatable({}, { __mode = "k" })
	S.threadLabel = setmetatable({}, { __mode = "k" })
	S.noYield = setmetatable({}, { __mode = "k" })
	local waitToken = setmetatable({}, { __mode = "k" })
	S.waitToken = waitToken
	S.contexts = {}

	local cocreate, coresume, costatus, corunning, coyield, coclose, coyieldable =
		coroutine.create,
		coroutine.resume,
		coroutine.status,
		coroutine.running,
		coroutine.yield,
		coroutine.close,
		coroutine.isyieldable
	local tbk = debug.traceback

	-- ---------------------------------------------------------------------------------------------
	--  Kontexte
	-- ---------------------------------------------------------------------------------------------
	function S.newContext(opts)
		local kind = opts.kind or "server"
		local ctx = {
			kind = kind,
			name = opts.name or kind,
			isServer = kind == "server" or kind == "harness",
			isClient = kind == "client",
			player = opts.player,
			game = opts.game,
			G = {},
			shared = {},
			modules = {},
			data = {},
		}
		S.contexts[#S.contexts + 1] = ctx
		return ctx
	end

	S.harnessCtx = S.newContext({ kind = "harness", name = "harness" })
	S.mainCtx = S.harnessCtx

	function S.setMainContext(ctx)
		S.mainCtx = ctx or S.harnessCtx
	end

	function S.ctx()
		local co = corunning()
		return S.threadCtx[co] or S.mainCtx
	end

	function S.setThreadContext(co, ctx)
		S.threadCtx[co] = ctx
	end

	-- ---------------------------------------------------------------------------------------------
	--  Threads
	-- ---------------------------------------------------------------------------------------------
	local function handler(e)
		return { e, tbk(Util.errToString(e), 2) }
	end

	function S.newThread(fn, ctx, label, onError)
		local co
		co = cocreate(function(...)
			local ok, info = xpcall(fn, handler, ...)
			if not ok then
				local msg, tb = info[1], info[2]
				local entry = Report.error({
					message = msg,
					traceback = tb,
					ctx = S.threadCtx[co],
					thread = co,
					kind = S.threadLabel[co] or "thread",
				})
				if onError then
					onError(msg, tb, entry)
				end
			end
		end)
		S.threadCtx[co] = ctx or S.ctx()
		if label then
			S.threadLabel[co] = label
		end
		return co
	end

	local depth = 0
	local flushing = false

	--- Setzt einen Thread fort (nur wenn "suspended"). Fehler roher Coroutinen werden gemeldet.
	function S.resume(co, ...)
		if costatus(co) ~= "suspended" then
			return false
		end
		depth += 1
		local ok, err = coresume(co, ...)
		depth -= 1
		if not ok then
			Report.error({
				message = err,
				traceback = tbk(co, Util.errToString(err)),
				ctx = S.threadCtx[co],
				thread = co,
				kind = S.threadLabel[co] or "thread",
			})
		end
		if depth == 0 and not flushing then
			S.flush()
		end
		return ok
	end

	--- Spiel-Funktion sofort in neuem Thread ausführen (Signal-Handler, Callbacks)
	function S.spawnHandler(fn, ctx, label, ...)
		local co = S.newThread(fn, ctx, label)
		S.resume(co, ...)
		return co
	end

	local function threadOrFn(v, fname)
		local t = type(v)
		if t == "function" then
			return S.newThread(v, S.ctx(), "task")
		elseif t == "thread" then
			return v
		end
		Util.badArg(1, fname, "function or thread", v)
	end

	function S.assertYieldable()
		local co = corunning()
		if S.noYield[co] or not coyieldable() then
			Util.raise("attempt to yield across metamethod/C-call boundary")
		end
		return co
	end

	-- task.spawn
	function S.spawn(fnOrThread, ...)
		local co = threadOrFn(fnOrThread, "spawn")
		local st = costatus(co)
		if st ~= "suspended" then
			Util.raise("cannot resume " .. st .. " coroutine")
		end
		waitToken[co] = nil
		S.resume(co, ...)
		return co
	end

	-- ---------------------------------------------------------------------------------------------
	--  Deferred-Queue (task.defer, Signal-Handler, Wait-Fortsetzungen)
	-- ---------------------------------------------------------------------------------------------
	local queue = {}
	S.queueLimit = 250000

	--- Reiht fn(a, b) für den nächsten Resumption-Punkt ein (Harness-intern)
	function S.queue(fn, a, b)
		queue[#queue + 1] = { fn, a, b }
	end

	local function resumeEntry(co, args)
		if args then
			S.resume(co, table.unpack(args, 1, args.n))
		else
			S.resume(co)
		end
	end
	function S.queueResume(co, args)
		queue[#queue + 1] = { resumeEntry, co, args }
	end

	function S.flush()
		if flushing then
			return
		end
		flushing = true
		local i = 1
		while i <= #queue do
			local e = queue[i]
			queue[i] = false
			i += 1
			local ok, err = xpcall(e[1], tbk, e[2], e[3])
			if not ok then
				Report.harnessError("Deferred-Eintrag fehlgeschlagen: " .. Util.errToString(err))
			end
			if i > S.queueLimit then
				Report.harnessError(
					"Deferred-Queue läuft über (> "
						.. S.queueLimit
						.. " Einträge in einem Resumption-Zyklus) – Endlosschleife aus Signalen?"
				)
				break
			end
		end
		table.clear(queue)
		flushing = false
	end

	function S.queueLength()
		return #queue
	end

	-- task.defer
	function S.defer(fnOrThread, ...)
		local co = threadOrFn(fnOrThread, "defer")
		local args = table.pack(...)
		S.queueResume(co, args)
		return co
	end

	-- ---------------------------------------------------------------------------------------------
	--  Timer (zwei Heaps: task.* und alte wait/spawn/delay)
	-- ---------------------------------------------------------------------------------------------
	local seq = 0
	local taskHeap, legacyHeap = {}, {}
	local function less(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.seq < b.seq
	end
	local function heapPush(h, e)
		h[#h + 1] = e
		local i = #h
		while i > 1 do
			local p = i // 2
			if less(h[i], h[p]) then
				h[i], h[p] = h[p], h[i]
				i = p
			else
				break
			end
		end
	end
	local function heapPop(h)
		local top = h[1]
		local n = #h
		h[1] = h[n]
		h[n] = nil
		n -= 1
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			if l <= n and less(h[l], h[m]) then
				m = l
			end
			if r <= n and less(h[r], h[m]) then
				m = r
			end
			if m == i then
				break
			end
			h[i], h[m] = h[m], h[i]
			i = m
		end
		return top
	end
	local function pushTimer(heap, t, co, token, args, mode)
		seq += 1
		heapPush(
			heap,
			{ t = t, f = S.frame + 1, seq = seq, co = co, token = token, args = args, mode = mode, start = S.now }
		)
	end
	S.pushTimer = function(t, co, args)
		pushTimer(taskHeap, t, co, nil, args, "delay")
	end
	--- Harness-Timer: fn() zur Simulationszeit t (im timers-Schritt, frühestens im nächsten Frame)
	function S.addTimer(t, fn)
		seq += 1
		heapPush(taskHeap, { t = t, f = S.frame + 1, seq = seq, fn = fn, mode = "fn", start = S.now })
	end

	local function wake(e)
		if e.mode == "fn" then
			-- Harness-Timer: Funktion im Haupt-Kontext ausführen
			local ok, err = xpcall(e.fn, tbk)
			if not ok then
				Report.harnessError("Harness-Timer fehlgeschlagen: " .. Util.errToString(err))
			end
			return
		end
		local co = e.co
		if e.token ~= nil then
			if waitToken[co] ~= e.token then
				return
			end
			waitToken[co] = nil
		end
		if costatus(co) ~= "suspended" then
			return
		end
		if e.mode == "legacy" then
			-- alte wait(): (verstrichen, elapsedTime); spawn/delay: Funktion bekommt dieselben Werte
			S.resume(co, math.max(S.now - e.start, e.t - e.start), S.now)
		elseif e.args then
			S.resume(co, table.unpack(e.args, 1, e.args.n))
		else
			S.resume(co)
		end
	end

	local function runTimers(heap)
		local later = nil
		while heap[1] and heap[1].t <= S.now + 1e-9 do
			local e = heapPop(heap)
			if e.f > S.frame then
				later = later or {}
				later[#later + 1] = e
			else
				wake(e)
			end
		end
		if later then
			for _, e in later do
				heapPush(heap, e)
			end
		end
	end

	-- task.wait
	function S.wait(t)
		local d = 0
		if t ~= nil then
			d = Util.checkNumber(t, 1, "wait")
			if d ~= d then
				d = 0
			end
		end
		local co = S.assertYieldable()
		local start = S.now
		local token = {}
		waitToken[co] = token
		pushTimer(taskHeap, S.now + math.max(d, 0), co, token, nil, "wait")
		coyield()
		-- tatsächlich verstrichene Zeit (nie kleiner als angefordert – Gleitkomma-Drift der Frame-Summe ausgleichen)
		return math.max(S.now - start, d)
	end

	-- task.delay
	function S.delay(t, fnOrThread, ...)
		local d = t == nil and 0 or Util.checkNumber(t, 1, "delay")
		local co = threadOrFn(fnOrThread, "delay")
		pushTimer(taskHeap, S.now + math.max(d, 0), co, nil, table.pack(...), "delay")
		return co
	end

	-- task.cancel
	function S.cancel(co)
		if type(co) ~= "thread" then
			Util.badArg(1, "cancel", "thread", co)
		end
		if co == corunning() then
			Util.raise("cannot cancel a running thread")
		end
		waitToken[co] = nil
		local st = costatus(co)
		if st == "suspended" then
			coclose(co)
		elseif st == "normal" then
			Util.raise("cannot cancel thread in normal state")
		end
	end

	-- alte wait(t): mind. ~1/30 s, Rückgabe (verstrichen, elapsedTime)
	function S.legacyWait(t)
		local d = 0
		if t ~= nil then
			d = Util.checkNumber(t, 1, "wait")
		end
		d = math.max(d, 1 / 30)
		local co = S.assertYieldable()
		local token = {}
		waitToken[co] = token
		pushTimer(legacyHeap, S.now + d, co, token, nil, "legacy")
		return coyield()
	end
	-- alte spawn(f): läuft nach ~1 Frame im Legacy-Wait-Schritt, Argumente (verstrichen, elapsedTime)
	function S.legacySpawn(fn)
		if type(fn) ~= "function" then
			Util.badArg(1, "spawn", "function", fn)
		end
		local co = S.newThread(fn, S.ctx(), "spawn")
		pushTimer(legacyHeap, S.now + 1 / 30, co, nil, nil, "legacy")
		return co
	end
	-- alte delay(t, f)
	function S.legacyDelay(t, fn)
		local d = t == nil and 0 or Util.checkNumber(t, 1, "delay")
		if type(fn) ~= "function" then
			Util.badArg(2, "delay", "function", fn)
		end
		local co = S.newThread(fn, S.ctx(), "delay")
		pushTimer(legacyHeap, S.now + math.max(d, 1 / 30), co, nil, nil, "legacy")
		return co
	end

	function S.pendingTimers()
		return #taskHeap + #legacyHeap
	end

	-- ---------------------------------------------------------------------------------------------
	--  Nicht-yieldende Callbacks
	-- ---------------------------------------------------------------------------------------------
	--- Führt fn in eigener Coroutine aus, die nicht yielden darf. Rückgabe wie pcall, bei Fehler zusätzlich Traceback.
	function S.callNoYield(fn, ...)
		local co = cocreate(fn)
		S.threadCtx[co] = S.ctx()
		S.noYield[co] = true
		local res = table.pack(coresume(co, ...))
		if costatus(co) == "suspended" then
			coclose(co)
			return false, "attempt to yield across metamethod/C-call boundary", ""
		end
		if not res[1] then
			return false, res[2], tbk(co, Util.errToString(res[2]))
		end
		return true, table.unpack(res, 2, res.n)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Harness-Aufrufe von Spiel-Code mit Ergebnis (für Szenarien)
	-- ---------------------------------------------------------------------------------------------
	--- Startet fn(…) in neuem Thread mit Kontext ctx; Rückgabe-Handle { done, ok, results, err }.
	function S.invoke(ctx, fn, ...)
		local h = { done = false }
		local co = S.newThread(
			function(...)
				h.results = table.pack(fn(...))
				h.ok = true
				h.done = true
			end,
			ctx,
			"invoke",
			function(msg, tb)
				h.ok = false
				h.err = msg
				h.traceback = tb
				h.done = true
			end
		)
		h.thread = co
		S.resume(co, ...)
		return h
	end

	--- Simuliert, bis das Handle fertig ist (oder timeout Sekunden vergangen sind). true wenn fertig.
	function S.await(h, timeout)
		return S.runUntil(function()
			return h.done
		end, timeout or 30)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Frame-Schleife
	-- ---------------------------------------------------------------------------------------------
	S.phases = {
		"network",
		"input",
		"render",
		"legacyWait",
		"preAnimation",
		"preSimulation",
		"physics",
		"postSimulation",
		"timers",
		"late",
	}
	S.hooks = {}
	for _, p in S.phases do
		S.hooks[p] = {}
	end

	--- Hook für eine Phase registrieren; Rückgabe: Funktion zum Entfernen
	function S.addHook(phase, fn, name)
		local list = S.hooks[phase]
		assert(list, "Harness: unbekannte Phase " .. tostring(phase))
		local h = { fn = fn, name = name or "?" }
		list[#list + 1] = h
		return function()
			local i = table.find(list, h)
			if i then
				table.remove(list, i)
			end
		end
	end

	local function runHooks(phase, dt)
		local list = S.hooks[phase]
		if #list == 0 then
			return
		end
		for _, h in table.clone(list) do
			local ok, err = xpcall(h.fn, tbk, dt, S.frame)
			if not ok then
				Report.harnessError("Hook " .. h.name .. " (" .. phase .. ") fehlgeschlagen: " .. Util.errToString(err))
			end
			S.flush()
		end
	end

	function S.step(dt)
		dt = dt or S.dt
		S.flush()
		S.frame += 1
		S.now += dt
		for _, phase in S.phases do
			if phase == "legacyWait" then
				runTimers(legacyHeap)
				S.flush()
			elseif phase == "timers" then
				runTimers(taskHeap)
				S.flush()
			end
			runHooks(phase, dt)
		end
		S.flush()
	end

	function S.run(seconds)
		local target = S.now + seconds
		while S.now < target - 1e-9 do
			S.step()
		end
	end

	--- Simuliert bis pred() wahr ist; Rückgabe true/false (Timeout)
	function S.runUntil(pred, timeout)
		local target = S.now + (timeout or 30)
		S.flush()
		while not pred() do
			if S.now >= target - 1e-9 then
				return false
			end
			S.step()
		end
		return true
	end

	-- ---------------------------------------------------------------------------------------------
	--  Uhren
	-- ---------------------------------------------------------------------------------------------
	function S.unix()
		return S.startUnix + S.now
	end
	function S.unixMillis()
		return math.floor((S.startUnix + S.now) * 1000)
	end

	return S
end
