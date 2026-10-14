--!nocheck
-- =====================================================================
--  Headless-Harness · RBXScriptSignal / RBXScriptConnection (SignalBehavior = Deferred)
--
--  Signal.new(name, owner?, opts?)  -> RBXScriptSignal-userdata (opts.onConnect(sig) beim ersten Connect)
--  Signal.fire(sig, …)              -> Deferred: jeder verbundene Handler läuft beim nächsten Resumption-Punkt
--                                      in einem NEUEN Thread mit dem Kontext des verbindenden Threads; Wait()
--                                      wird ebenfalls verzögert fortgesetzt. Once trennt beim Feuern.
--                                      Getrennte Verbindungen (Disconnect/Destroy) vor der Ausführung laufen nicht.
--  Signal.fireImmediate(sig, …)     -> Handler sofort (je neuer Thread) – nur für Sonderfälle (Destroying)
--  Signal.disconnectAll(sig), Signal.count(sig), Signal.totalByName[name] (aktive Verbindungen je Event-Name)
--  Signal.connectInternal(sig, fn)  -> Harness-Listener (läuft deferred im Haupt-Kontext, kein Spiel-Thread)
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local raise = Util.raise
	local getmt = getmetatable
	local Signal = {}

	Signal.totalByName = setmetatable({}, {
		__index = function()
			return 0
		end,
	})
	local totalByName = Signal.totalByName

	local sigIndex, connIndex
	local sigMethods, connMethods = {}, {}

	local function readonly(_, k)
		raise(tostring(k) .. " cannot be assigned to")
	end

	function Signal.new(name, owner, opts)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = sigIndex
		mt.__newindex = readonly
		mt.__type = "RBXScriptSignal"
		mt.__tostring = function()
			return "Signal " .. name
		end
		mt.name = name
		mt.owner = owner
		mt.conns = {}
		mt.waiting = {}
		mt.onConnect = opts and opts.onConnect
		mt.onDisconnectAll = opts and opts.onDisconnectAll
		return u
	end

	local function isSignal(v)
		local mt = Util.hostMeta(v)
		return mt ~= nil and mt.__index == sigIndex
	end
	Signal.isSignal = isSignal

	local function selfSig(self, m)
		local mt = Util.hostMeta(self)
		if not mt or mt.__index ~= sigIndex then
			raise("Expected ':' not '.' calling member function " .. m)
		end
		return mt
	end

	function sigIndex(self, k)
		local f = sigMethods[k]
		if f then
			return f
		end
		raise(tostring(k) .. " is not a valid member of RBXScriptSignal")
	end
	Util.registerHostIndex(sigIndex)

	-- ---------------------------------------------------------------------------------------------
	--  Verbindungen
	-- ---------------------------------------------------------------------------------------------
	function connIndex(self, k)
		local m = getmt(self)
		if k == "Connected" then
			return m.connected
		end
		local f = connMethods[k]
		if f then
			return f
		end
		raise(tostring(k) .. " is not a valid member of RBXScriptConnection")
	end
	Util.registerHostIndex(connIndex)

	local function removeConn(smt, c)
		local list = smt.conns
		for i = #list, 1, -1 do
			if list[i] == c then
				table.remove(list, i)
				break
			end
		end
	end

	local function disconnect(c)
		local m = getmt(c)
		if not m.connected then
			return
		end
		m.connected = false
		local smt = getmt(m.sig)
		removeConn(smt, c)
		totalByName[smt.name] = totalByName[smt.name] - 1
	end
	Signal.disconnect = disconnect

	function connMethods.Disconnect(self)
		local m = Util.hostMeta(self)
		if not m or m.__index ~= connIndex then
			raise("Expected ':' not '.' calling member function Disconnect")
		end
		disconnect(self)
	end
	function connMethods.disconnect(self)
		Report.deprecatedUse("RBXScriptConnection:disconnect")
		return connMethods.Disconnect(self)
	end

	local function connect(self, fn, once, mname, internal)
		local smt = selfSig(self, mname)
		if type(fn) ~= "function" then
			raise("Attempt to connect failed: Passed value is not a function")
		end
		local c = newproxy(true)
		local m = getmt(c)
		m.__index = connIndex
		m.__newindex = readonly
		m.__type = "RBXScriptConnection"
		m.__tostring = function()
			return "Connection"
		end
		m.sig = self
		m.fn = fn
		m.ctx = Sched.ctx()
		m.connected = true
		m.once = once
		m.internal = internal
		local list = smt.conns
		list[#list + 1] = c
		totalByName[smt.name] = totalByName[smt.name] + 1
		if smt.onConnect and #list == 1 then
			smt.onConnect(self)
		end
		return c
	end

	function sigMethods.Connect(self, fn)
		return connect(self, fn, false, "Connect")
	end
	function sigMethods.connect(self, fn)
		Report.deprecatedUse("RBXScriptSignal:connect")
		return connect(self, fn, false, "connect")
	end
	function sigMethods.Once(self, fn)
		return connect(self, fn, true, "Once")
	end
	function sigMethods.ConnectParallel(self, fn)
		-- Keine Actors im Harness: wie Connect (Handler läuft seriell)
		Report.unmockedCall("RBXScriptSignal", "ConnectParallel(seriell)", "method")
		return connect(self, fn, false, "ConnectParallel")
	end
	function sigMethods.Wait(self)
		local smt = selfSig(self, "Wait")
		local co = Sched.assertYieldable()
		smt.waiting[#smt.waiting + 1] = co
		return coroutine.yield()
	end
	function sigMethods.wait(self)
		Report.deprecatedUse("RBXScriptSignal:wait")
		return sigMethods.Wait(self)
	end

	--- Harness-Listener (kein Spiel-Thread; Fehler = Harness-Fehler)
	function Signal.connectInternal(sig, fn)
		return connect(sig, fn, false, "Connect", true)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Feuern
	-- ---------------------------------------------------------------------------------------------
	local function runConn(c, args)
		local m = getmt(c)
		if not m.connected and not m.forceOnce then
			return
		end
		if m.forceOnce then
			m.forceOnce = nil
		end
		if m.internal then
			local ok, err = xpcall(m.fn, debug.traceback, table.unpack(args, 1, args.n))
			if not ok then
				Report.harnessError("interner Signal-Listener fehlgeschlagen: " .. Util.errToString(err))
			end
			return
		end
		Sched.spawnHandler(m.fn, m.ctx, "signal:" .. getmt(m.sig).name, table.unpack(args, 1, args.n))
	end

	local function runConnForced(c, args)
		getmt(c).forceOnce = true
		runConn(c, args)
	end

	function Signal.fire(sig, ...)
		local smt = getmt(sig)
		local list, waiting = smt.conns, smt.waiting
		if #list == 0 and #waiting == 0 then
			return
		end
		local args = table.pack(...)
		if #list > 0 then
			for _, c in table.clone(list) do
				local m = getmt(c)
				if m.connected then
					if m.once then
						disconnect(c)
						Sched.queue(runConnForced, c, args)
					else
						Sched.queue(runConn, c, args)
					end
				end
			end
		end
		if #waiting > 0 then
			smt.waiting = {}
			for _, co in waiting do
				Sched.queueResume(co, args)
			end
		end
	end

	--- Sofort feuern (Handler laufen jetzt, je in neuem Thread). Für Destroying u. ä.
	function Signal.fireImmediate(sig, ...)
		local smt = getmt(sig)
		local args = table.pack(...)
		for _, c in table.clone(smt.conns) do
			local m = getmt(c)
			if m.connected then
				if m.once then
					disconnect(c)
					runConnForced(c, args)
				else
					runConn(c, args)
				end
			end
		end
		if #smt.waiting > 0 then
			local waiting = smt.waiting
			smt.waiting = {}
			for _, co in waiting do
				Sched.resume(co, table.unpack(args, 1, args.n))
			end
		end
	end

	function Signal.disconnectAll(sig)
		local smt = getmt(sig)
		for _, c in table.clone(smt.conns) do
			disconnect(c)
		end
		-- wartende Threads bleiben (wie Roblox) für immer hängen
		smt.waiting = {}
		if smt.onDisconnectAll then
			smt.onDisconnectAll(sig)
		end
	end

	function Signal.count(sig)
		return #getmt(sig).conns
	end

	function Signal.hasWaiting(sig)
		return #getmt(sig).waiting > 0
	end

	function Signal.name(sig)
		return getmt(sig).name
	end

	return Signal
end
