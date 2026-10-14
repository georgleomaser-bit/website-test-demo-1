--!nocheck
-- =====================================================================
--  Headless-Harness · Script-Umgebungen (Roblox-Globals je Kontext) + require
--
--  G.base(ctx)                 -> Tabelle mit allen Roblox-Globals für diesen Kontext (gecacht in ctx.data.base):
--                                 game/workspace (ctx.game), Instance, Enum, alle Datentypen, task, wait/spawn/delay
--                                 (deprecated gezählt), tick/time/elapsedTime/os.* (SIMULIERTE Zeit; os.date auf dem
--                                 Server in UTC), typeof/type ("vector" für Vector3)/getmetatable (gesperrt),
--                                 print/warn (-> Report), shared/_G je Kontext, coroutine.create/wrap (erben Kontext),
--                                 debug/utf8-Polyfills, settings()/UserSettings(), loadstring (gesperrt wie Roblox).
--                                 Unbekannte Globals sind nil (Whitelist, keine CLI-Extras).
--  G.makeEnv(ctx, scriptInst)  -> eigene Umgebung je Skript (script, require), __index = G.base(ctx)
--  G.compile(source, chunkName)-> Funktion oder nil, Fehler (Syntaxfehler werden gemeldet)
--  G.startScript(ctx, scriptInst, source, chunkName, immediate) -> Thread (Script-Start in eigenem Thread)
--  G.require(ctx, moduleScript)-> Roblox-require: Cache JE KONTEXT, "Requested module was required recursively",
--                                 "Module code did not return exactly one value", Fehler im Modul ->
--                                 "Requested module experienced an error while loading" (Original im Report).
--  G.moduleProvider = function(moduleScript) -> source, chunkName   (Standard: Inst.setScriptSource-Ablage)
--  G.requireHooks               Liste von fn(ctx, moduleScript, wert, chunkName) nach jedem erfolgreichen require
--                               (Szenarien hängen sich so z. B. an PlayerStateService.Handle)
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local DT = R.DT
	local Inst = R.Inst
	local raise = Util.raise
	local G = {}

	-- Standard: Quelltext aus Inst.setScriptSource (M.ext.source/chunkName); der Bundler kann das ersetzen
	G.moduleProvider = function(m)
		local src, chunk = Inst.scriptSource(m)
		if src then
			return src, chunk or Inst.fullName(m)
		end
		return nil
	end

	local function noop() end

	local function joinArgs(...)
		local n = select("#", ...)
		local parts = table.create(n)
		for i = 1, n do
			parts[i] = tostring((select(i, ...)))
		end
		return table.concat(parts, " ")
	end
	G.joinArgs = joinArgs

	-- utf8-Ergänzungen, die der CLI fehlen
	local utf8lib = {}
	for k, v in utf8 do
		utf8lib[k] = v
	end
	if utf8lib.graphemes == nil then
		utf8lib.graphemes = function(s, i, j)
			local starts = {}
			for p in utf8.codes(s) do
				starts[#starts + 1] = p
			end
			local idx = 0
			return function()
				idx += 1
				local st = starts[idx]
				if st == nil then
					return nil
				end
				local nx = starts[idx + 1]
				return st, (nx and nx - 1 or #s)
			end
		end
	end
	utf8lib.nfcnormalize = utf8lib.nfcnormalize or function(s)
		return s
	end
	utf8lib.nfdnormalize = utf8lib.nfdnormalize or function(s)
		return s
	end
	table.freeze(utf8lib)

	local debuglib = {
		traceback = debug.traceback,
		info = debug.info,
		profilebegin = noop,
		profileend = noop,
		setmemorycategory = noop,
		resetmemorycategory = noop,
		getmemorycategory = function()
			return "main"
		end,
		dumpcodesize = noop,
	}
	table.freeze(debuglib)

	local corolib = {}
	for k, v in coroutine do
		corolib[k] = v
	end
	corolib.create = function(f)
		if type(f) ~= "function" then
			Util.badArg(1, "create", "function", f)
		end
		local co = coroutine.create(f)
		Sched.threadCtx[co] = Sched.ctx()
		return co
	end
	corolib.wrap = function(f)
		if type(f) ~= "function" then
			Util.badArg(1, "wrap", "function", f)
		end
		local co = coroutine.create(f)
		Sched.threadCtx[co] = Sched.ctx()
		return function(...)
			local r = table.pack(coroutine.resume(co, ...))
			if not r[1] then
				error(r[2], 0)
			end
			return table.unpack(r, 2, r.n)
		end
	end
	table.freeze(corolib)

	local taskLib = {
		spawn = Sched.spawn,
		defer = Sched.defer,
		delay = Sched.delay,
		wait = Sched.wait,
		cancel = Sched.cancel,
		synchronize = noop,
		desynchronize = noop,
	}
	table.freeze(taskLib)

	-- os mit simulierter Zeit; Server-Lokalzeit = UTC
	local function simTime(t)
		if t == nil then
			return math.floor(Sched.unix())
		end
		if type(t) ~= "table" then
			Util.badArg(1, "time", "table", t)
		end
		local ctx = Sched.ctx()
		if ctx.isClient then
			return os.time(t)
		end
		local y, m, d = t.year, t.month, t.day
		if y == nil or m == nil or d == nil then
			raise("field 'day' missing in date table")
		end
		-- Normalisierung von Überläufen über Tage/Sekunden
		local mm = m - 1
		y += mm // 12
		m = mm % 12 + 1
		return DT.timegm(y, m, 1, 0, 0, 0) + (d - 1) * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
	end
	local function simDate(fmt, t)
		fmt = fmt or "%c"
		if t == nil then
			t = math.floor(Sched.unix())
		end
		local ctx = Sched.ctx()
		if not ctx.isClient and string.sub(fmt, 1, 1) ~= "!" then
			fmt = "!" .. fmt
		end
		return os.date(fmt, t)
	end
	local oslib = {
		time = simTime,
		date = simDate,
		clock = function()
			return Sched.fineTime()
		end,
		difftime = os.difftime,
	}
	table.freeze(oslib)

	local function collect(opt)
		if opt == "count" then
			return gcinfo()
		end
		raise("collectgarbage must be called with 'count'; use gcinfo() instead")
	end

	-- settings()/UserSettings()
	local settingsNames = {
		RenderSettings = "Rendering",
		PhysicsSettings = "Physics",
		NetworkSettings = "Network",
		DebugSettings = "Diagnostics",
		GameSettings = "Game Options",
		LuaSettings = "Lua",
	}
	local function settingsObject(ctx)
		local s = ctx.data.settings
		if s == nil then
			s = Inst.create("GlobalSettings", { Name = "GlobalSettings" })
			local M = getmetatable(s)
			M.ext = { services = {} }
			for cls, name in settingsNames do
				if Inst.class(cls) then
					local svc = Inst.service(s, cls)
					getmetatable(svc).name = name
				end
			end
			ctx.data.settings = s
		end
		return s
	end
	local function userSettingsObject(ctx)
		local s = ctx.data.userSettings
		if s == nil then
			s = Inst.create("UserSettings", { Name = "UserSettings" })
			getmetatable(s).ext = { services = {} }
			Inst.service(s, "UserGameSettings")
			ctx.data.userSettings = s
		end
		return s
	end

	local whitelist = {
		"assert",
		"error",
		"gcinfo",
		"getfenv",
		"setfenv",
		"ipairs",
		"newproxy",
		"next",
		"pairs",
		"pcall",
		"rawequal",
		"rawget",
		"rawlen",
		"rawset",
		"select",
		"setmetatable",
		"tonumber",
		"tostring",
		"unpack",
		"xpcall",
		"string",
		"table",
		"math",
		"bit32",
		"buffer",
		"vector",
	}

	-- ---------------------------------------------------------------------------------------------
	--  pcall/xpcall des Spiels: Fehler werden trotzdem erfasst (Report.caught, mit Traceback am Fehlerort)
	--  – das Spiel fängt viele Fehler ab und warnt nur; ohne das würden echte Bugs übersehen.
	-- ---------------------------------------------------------------------------------------------
	local rawxpcall = xpcall
	local function captureHandler(e)
		Report.caught(e, 2)
		return e
	end
	local function gamePcall(f, ...)
		return rawxpcall(f, captureHandler, ...)
	end
	local function gameXpcall(f, handler, ...)
		if type(handler) ~= "function" then
			-- Roblox/Luau: xpcall ohne gültigen Handler -> Fehler beim Fehlerfall; hier wie pcall + Handler-Fehler
			return rawxpcall(f, handler, ...)
		end
		return rawxpcall(f, function(e)
			Report.caught(e, 2)
			return handler(e)
		end, ...)
	end
	G.gamePcall = gamePcall

	function G.base(ctx)
		local b = ctx.data.base
		if b then
			return b
		end
		b = {}
		for _, k in whitelist do
			b[k] = _G[k]
		end
		b._VERSION = "Luau"
		b.pcall = gamePcall
		b.xpcall = gameXpcall
		b.ypcall = gamePcall
		b.typeof = Util.typeof
		b.type = Util.type
		b.getmetatable = Util.getmetatable
		b.utf8 = utf8lib
		b.debug = debuglib
		b.coroutine = corolib
		b.task = taskLib
		b.os = oslib
		b.collectgarbage = collect
		b.Instance = Inst.global
		b.Enum = R.Enum.global
		for _, name in DT.globalNames do
			if DT[name] ~= nil then
				b[name] = DT[name]
			end
		end
		-- veraltete Zeit-/Thread-Funktionen
		b.wait = function(t)
			Report.deprecatedUse("wait")
			return Sched.legacyWait(t)
		end
		b.Wait = b.wait
		b.spawn = function(f)
			Report.deprecatedUse("spawn")
			return Sched.legacySpawn(f)
		end
		b.Spawn = b.spawn
		b.delay = function(t, f)
			Report.deprecatedUse("delay")
			return Sched.legacyDelay(t, f)
		end
		b.Delay = b.delay
		b.tick = function()
			return Sched.startUnix + Sched.fineTime()
		end
		b.time = function()
			return Sched.now
		end
		b.elapsedTime = function()
			return Sched.now
		end
		b.ElapsedTime = b.elapsedTime
		b.version = function()
			return "0.700.0.7000000"
		end
		b.Version = b.version
		b.printidentity = function(prefix)
			Report.print(Sched.ctx(), "print", (prefix or "Current identity is") .. " 2")
		end
		b.print = function(...)
			Report.print(Sched.ctx(), "print", joinArgs(...))
		end
		b.warn = function(...)
			local text = joinArgs(...)
			local ctx2 = Sched.ctx()
			Report.print(ctx2, "warn", text)
			Report.warn(text, ctx2, debug.traceback("", 2), "gameWarn")
		end
		b.loadstring = function()
			raise("loadstring() is not available")
		end
		b.settings = function()
			return settingsObject(ctx)
		end
		b.UserSettings = function()
			return userSettingsObject(ctx)
		end
		b.stats = function()
			Report.deprecatedUse("stats")
			return ctx.game and Inst.service(ctx.game, "Stats")
		end
		b.Stats = b.stats
		b.PluginManager = function()
			raise("PluginManager can only be used by plugins")
		end
		b.DebuggerManager = function()
			raise("DebuggerManager is not accessible")
		end
		b.shared = ctx.shared
		b._G = ctx.G
		if ctx.game then
			b.game = ctx.game
			b.Game = ctx.game
			local ws = Inst.findServiceRaw(ctx.game, "Workspace")
			b.workspace = ws
			b.Workspace = ws
		end
		b.require = function(target)
			return G.require(ctx, target)
		end
		ctx.data.base = b
		return b
	end

	--- Neue Umgebung für ein Skript/Modul
	function G.makeEnv(ctx, scriptInst)
		local base = G.base(ctx)
		local env = setmetatable({}, { __index = base })
		env.script = scriptInst
		env.require = function(target)
			return G.require(ctx, target)
		end
		return env
	end

	function G.compile(source, chunkName)
		local fn, err = loadstring(source, "=" .. chunkName)
		if not fn then
			Report.error({ message = err, traceback = err, ctx = Sched.ctx(), kind = "compile" })
			return nil, err
		end
		return fn
	end

	--- Script starten (eigener Thread mit Kontext ctx). immediate=false -> per task.defer.
	function G.startScript(ctx, scriptInst, source, chunkName, immediate)
		local fn = G.compile(source, chunkName)
		if not fn then
			return nil
		end
		setfenv(fn, G.makeEnv(ctx, scriptInst))
		local co = Sched.newThread(fn, ctx, "script:" .. chunkName)
		if immediate == false then
			Sched.queueResume(co, nil)
		else
			Sched.resume(co)
		end
		return co
	end

	-- -------------------------------------------------------------------------------------------------
	--  require
	-- -------------------------------------------------------------------------------------------------
	local function handler(e)
		return { e, debug.traceback(Util.errToString(e), 2) }
	end

	-- Harness: Funktionen (ctx, moduleScript, rückgabewert, chunkName), die nach jedem erfolgreichen require laufen
	G.requireHooks = {}

	local function wakeAll(entry)
		local ws = entry.waiters
		entry.waiters = {}
		for _, co in ws do
			Sched.queueResume(co, nil)
		end
	end

	function G.require(ctx, target)
		if type(target) == "number" then
			Report.unmockedCall("require", "AssetId", "global")
			raise("require(assetId) is not supported in the headless harness (asset " .. tostring(target) .. ")")
		end
		local M = Inst.meta(target)
		if M == nil or not M.cls.isA.ModuleScript then
			raise("Attempted to call require with invalid argument(s).")
		end
		local cache = ctx.modules
		local entry = cache[target]
		local co = coroutine.running()
		while entry and entry.state == "loading" do
			if entry.threads[co] then
				raise("Requested module was required recursively")
			end
			Sched.assertYieldable()
			table.insert(entry.waiters, co)
			coroutine.yield()
			entry = cache[target]
		end
		if entry then
			if entry.state == "done" then
				return entry.value
			end
			raise("Requested module experienced an error while loading")
		end
		local provider = G.moduleProvider
		local src, chunk
		if provider then
			src, chunk = provider(target)
		end
		if src == nil then
			Report.harnessError(
				"Kein Quelltext für ModuleScript " .. Inst.fullName(target) .. " (moduleProvider fehlt?)"
			)
			raise("Requested module experienced an error while loading")
		end
		entry = { state = "loading", threads = { [co] = true }, waiters = {} }
		-- verschachtelte requires im selben Thread erkennen (Kette A -> B -> A)
		cache[target] = entry
		local fn, cerr = loadstring(src, "=" .. chunk)
		if not fn then
			entry.state = "error"
			Report.error({ message = cerr, traceback = cerr, ctx = ctx, kind = "compile" })
			wakeAll(entry)
			raise("Requested module experienced an error while loading")
		end
		setfenv(fn, G.makeEnv(ctx, target))
		local res = table.pack(xpcall(fn, handler))
		if not res[1] then
			entry.state = "error"
			local info = res[2]
			Report.error({ message = info[1], traceback = info[2], ctx = ctx, thread = co, kind = "require" })
			wakeAll(entry)
			raise("Requested module experienced an error while loading")
		end
		if res.n ~= 2 then
			entry.state = "error"
			wakeAll(entry)
			raise("Module code did not return exactly one value")
		end
		entry.state = "done"
		entry.value = res[2]
		-- Harness-Beobachter (Szenarien: z. B. Spion auf PlayerStateService.Handle) – vor dem ersten Rückgabewert
		for _, hook in G.requireHooks do
			local okHook, errHook = xpcall(hook, debug.traceback, ctx, target, entry.value, chunk)
			if not okHook then
				Report.harnessError("require-Hook fehlgeschlagen: " .. tostring(errHook))
			end
		end
		wakeAll(entry)
		return entry.value
	end

	return G
end
